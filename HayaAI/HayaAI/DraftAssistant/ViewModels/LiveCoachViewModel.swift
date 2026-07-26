import Foundation
import Combine
import SwiftUI

// MARK: - Live Coach View Model
/// Bridges `GameSessionManager` to the SwiftUI live coach view.
/// All in-game state, alerts, advice, and hero recommendations flow through here.
@MainActor
final class LiveCoachViewModel: ObservableObject {

    // MARK: - Published
    @Published private(set) var gameState: LiveGameState = LiveGameState()
    @Published private(set) var activeAlerts: [CoachAlert] = []
    @Published private(set) var topAlert: CoachAlert? = nil
    @Published private(set) var turtleTimer: ObjectiveTimer = ObjectiveTimer(type: .turtle)
    @Published private(set) var lordTimer: ObjectiveTimer = ObjectiveTimer(type: .lord)
    @Published private(set) var currentAdvice: String = ""
    @Published private(set) var sessionPhase: GameSessionPhase = .idle
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var killScore: KillScore = KillScore()
    @Published var showAlertDetail: CoachAlert? = nil
    @Published private(set) var recentAlertHistory: [CoachAlert] = []

    // In-game recommendation state
    @Published private(set) var inGamePackage: InGameRecommendationPackage? = nil
    @Published private(set) var selectedRecommendationTab: InGameTab = .build
    @Published private(set) var isGeneratingRecommendation: Bool = false

    // MARK: - In-Game Tab
    enum InGameTab: String, CaseIterable {
        case build = "Build"
        case targets = "Targets"
        case rotation = "Rotation"
        case tips = "Tips"

        var icon: String {
            switch self {
            case .build: return "hammer.fill"
            case .targets: return "scope"
            case .rotation: return "arrow.triangle.turn.up.right.circle.fill"
            case .tips: return "lightbulb.fill"
            }
        }
    }

    // MARK: - Dependencies
    let gameSessionManager: GameSessionManager
    private let inGameRecommendationService: InGameRecommendationService

    // MARK: - Subscriptions
    private var cancellables: Set<AnyCancellable> = []
    private var adviceUpdateTask: Task<Void, Never>? = nil

    init(gameSessionManager: GameSessionManager) {
        self.gameSessionManager = gameSessionManager
        self.inGameRecommendationService = InGameRecommendationService(
            heroDatabase: gameSessionManager.draftStateManager.heroDatabase
        )
        bindGameSession()
        startPeriodicAdviceRefresh()
    }

    func selectTab(_ tab: InGameTab) {
        selectedRecommendationTab = tab
    }

    // MARK: - Session Control

    func startSession() async {
        do {
            try await gameSessionManager.startSession()
        } catch {
            // Surface error via alert
            let alert = CoachAlert(
                id: UUID().uuidString,
                type: .gameOver,
                priority: .high,
                message: "Failed to start capture",
                detail: error.localizedDescription,
                action: nil,
                triggeredAt: Date(),
                expiresAt: Date().addingTimeInterval(10)
            )
            activeAlerts.insert(alert, at: 0)
        }
    }

    func endSession() async {
        await gameSessionManager.endSession()
    }

    func dismissAlert(_ alert: CoachAlert) {
        gameSessionManager.dismissAlert(id: alert.id)
        recentAlertHistory.insert(alert, at: 0)
        if recentAlertHistory.count > 20 { recentAlertHistory.removeLast() }
    }

    func dismissTopAlert() {
        guard let top = topAlert else { return }
        dismissAlert(top)
    }

    func manualObjectiveKill(_ objective: Objective, team: DraftTurn) {
        Task { await gameSessionManager.recordObjectiveKilled(objective, by: team) }
    }

    func setPhase(_ phase: GameSessionPhase) {
        gameSessionManager.manuallySetPhase(phase)
    }

    // MARK: - Bindings

    private func bindGameSession() {
        gameSessionManager.$liveGameState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.gameState = state
                self.killScore = state.killScore
                self.activeAlerts = state.activeAlerts.filter { $0.isActive }
                self.topAlert = self.activeAlerts.first
                self.turtleTimer = state.objectives.turtle
                self.lordTimer = state.objectives.lord
                // Regenerate in-game recommendations when game state changes
                Task { await self.refreshInGameRecommendations(gameState: state) }
            }
            .store(in: &cancellables)

        gameSessionManager.$sessionPhase
            .receive(on: RunLoop.main)
            .assign(to: &$sessionPhase)

        gameSessionManager.$isActive
            .receive(on: RunLoop.main)
            .assign(to: &$isCapturing)
    }

    private func startPeriodicAdviceRefresh() {
        adviceUpdateTask = Task {
            while !Task.isCancelled {
                currentAdvice = await gameSessionManager.liveCoachEngine.currentPhaseAdvice(state: gameState)
                try? await Task.sleep(nanoseconds: 3_000_000_000) // refresh advice every 3s
            }
        }
    }

    private func refreshInGameRecommendations(gameState: LiveGameState) async {
        guard gameState.sessionPhase.isInGame else { return }
        let draftState = gameSessionManager.draftStateManager.currentDraftState
        let playerHero = draftState.friendlyPicks.first { $0.status == .locked }?.heroName ?? ""
        guard !playerHero.isEmpty else { return }

        isGeneratingRecommendation = true
        if let package = await inGameRecommendationService.generatePackage(
            playerHeroName: playerHero,
            draftState: draftState,
            gameState: gameState
        ) {
            inGamePackage = package
            // Sync one-liner into currentAdvice when recommendation is fresh
            currentAdvice = package.oneLineAdvice
        }
        isGeneratingRecommendation = false
    }

    deinit {
        adviceUpdateTask?.cancel()
    }

    // MARK: - Computed helpers

    var gameTimeFormatted: String { gameState.gameTimeFormatted }

    var killLeadText: String {
        let lead = killScore.killLead
        if lead > 0 { return "+\(lead) kills ahead" }
        if lead < 0 { return "\(lead) kills behind" }
        return "Even in kills"
    }

    var killLeadColor: Color {
        let lead = killScore.killLead
        if lead > 2 { return .green }
        if lead < -2 { return .red }
        return .orange
    }

    var turtleStatusText: String {
        switch turtleTimer.status {
        case .alive: return "Turtle is ALIVE"
        case .dead:
            if let secs = turtleTimer.secondsUntilSpawn { return "Turtle in \(secs)s" }
            return "Turtle dead"
        case .respawning:
            if let secs = turtleTimer.secondsUntilSpawn { return "Turtle in \(secs)s" }
            return "Respawning..."
        case .unknown: return "Turtle ?"
        }
    }

    var lordStatusText: String {
        switch lordTimer.status {
        case .alive: return "LORD is ALIVE"
        case .dead:
            if let secs = lordTimer.secondsUntilSpawn { return "Lord in \(secs)s" }
            return "Lord dead"
        case .respawning:
            if let secs = lordTimer.secondsUntilSpawn { return "Lord in \(secs)s" }
            return "Not spawned yet"
        case .unknown: return "Lord ?"
        }
    }

    var turtleUrgency: AlertPriority {
        guard let secs = turtleTimer.secondsUntilSpawn else {
            return turtleTimer.status == .alive ? .critical : .low
        }
        if secs <= 20 { return .critical }
        if secs <= 60 { return .high }
        return .low
    }

    var lordUrgency: AlertPriority {
        guard let secs = lordTimer.secondsUntilSpawn else {
            return lordTimer.status == .alive ? .critical : .low
        }
        if secs <= 20 { return .critical }
        if secs <= 60 { return .high }
        return .low
    }
}
