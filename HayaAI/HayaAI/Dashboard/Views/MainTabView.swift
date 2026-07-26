import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var heroDatabaseService: HeroDatabaseService

    @StateObject private var draftStateManager: DraftStateManager
    @StateObject private var draftViewModel: DraftAssistantViewModel
    @StateObject private var dashboardViewModel: DashboardViewModel

    init() {
        // These are initialised once here and shared down the view hierarchy
        let db = HeroDatabaseService()
        let dsm = DraftStateManager(heroDatabase: db)
        let recEngine = RecommendationEngine(heroDatabase: db)
        let itemEngine = ItemRecommendationEngine()
        let strategyEngine = StrategyEngine()
        let replayKitManager = ReplayKitManager()
        let visionEngine = VisionEngine(heroNames: [])

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
    }

    var body: some View {
        TabView(selection: $appRouter.selectedTab) {
            DashboardView()
                .environmentObject(dashboardViewModel)
                .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
                .tag(AppTab.dashboard)

            DraftAssistantView()
                .environmentObject(draftViewModel)
                .environmentObject(draftStateManager)
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
    }
}
