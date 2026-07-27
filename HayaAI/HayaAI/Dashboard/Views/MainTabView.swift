import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var heroDatabaseService: HeroDatabaseService

    @StateObject private var draftStateManager: DraftStateManager
    @StateObject private var draftViewModel: DraftAssistantViewModel
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var sessionManager: GameSessionManager
    @StateObject private var liveCoachViewModel: LiveCoachViewModel

    init() {
        let db = HeroDatabaseService()
        let dsm = DraftStateManager(heroDatabase: db)
        let recEngine = RecommendationEngine(heroDatabase: db)
        let itemEngine = ItemRecommendationEngine()
        let strategyEngine = StrategyEngine()
        let replayKitManager = ReplayKitManager()
        let visionEngine = VisionEngine(heroNames: [])

        // GameSessionManager owns the ReplayKit manager — shared with DraftAssistantViewModel
        let gsm = GameSessionManager(
            replayKitManager: replayKitManager,
            draftStateManager: dsm,
            heroDatabase: db
        )
        let lcvm = LiveCoachViewModel(gameSessionManager: gsm)

        _draftStateManager = StateObject(wrappedValue: dsm)
        _draftViewModel = StateObject(wrappedValue: DraftAssistantViewModel(
            draftStateManager: dsm,
            recommendationEngine: recEngine,
            itemEngine: itemEngine,
            strategyEngine: strategyEngine,
            replayKitManager: replayKitManager,
            visionEngine: visionEngine
        ))
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(heroDatabase: db))
        _sessionManager = StateObject(wrappedValue: gsm)
        _liveCoachViewModel = StateObject(wrappedValue: lcvm)
    }

    var body: some View {
        TabView(selection: $appRouter.selectedTab) {
            DashboardView()
                .environmentObject(dashboardViewModel)
                .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
                .tag(AppTab.dashboard)

            // Draft + Live Coach in one container — transitions automatically
            GameModeContainerView(
                liveCoachViewModel: liveCoachViewModel,
                sessionManager: sessionManager
            )
            .environmentObject(draftViewModel)
            .environmentObject(draftStateManager)
            .environmentObject(liveCoachViewModel)
            .tabItem { Label(AppTab.draftAssistant.title, systemImage: AppTab.draftAssistant.systemImage) }
            .tag(AppTab.draftAssistant)

            AnalyticsDashboardView()
                .tabItem { Label(AppTab.analytics.title, systemImage: AppTab.analytics.systemImage) }
                .tag(AppTab.analytics)

            SettingsView()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .tint(Color.hayaGold)
        .preferredColorScheme(.dark)
        // ── Auto-activate coaching overlay ──────────────────────────────────
        // When the Broadcast Extension starts writing frames (user started a
        // screen broadcast from MLBB or Control Center), automatically kick off
        // the coaching session so the Dynamic Island Live Activity and
        // notification banners appear without the user having to return to
        // Haya AI and tap anything.
        .onReceive(draftViewModel.broadcastFrameReader.$broadcastStatus) { status in
            Task { @MainActor in
                if status == "running", !liveCoachViewModel.isCapturing {
                    await liveCoachViewModel.startSession()
                } else if status != "running", liveCoachViewModel.isCapturing {
                    await liveCoachViewModel.endSession()
                }
            }
        }
        // Re-arm the reader whenever the app returns to the foreground in case
        // the OS paused it while backgrounded for an extended period.
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            draftViewModel.broadcastFrameReader.start()
        }
    }
}
