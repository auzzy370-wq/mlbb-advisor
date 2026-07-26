import Foundation
import Combine
import SwiftUI

@MainActor
final class DraftAssistantViewModel: ObservableObject {

    // MARK: - Published State
    @Published private(set) var draftState: DraftState = DraftState()
    @Published private(set) var recommendations: [HeroRecommendation] = []
    @Published private(set) var topRecommendation: HeroRecommendation? = nil
    @Published private(set) var strategy: DraftStrategy? = nil
    @Published private(set) var teamAnalysis: TeamCompositionAnalysis = TeamCompositionAnalysis()
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var captureError: String? = nil
    @Published private(set) var selectedTab: DraftTab = .recommendations
    @Published var selectedRecommendation: HeroRecommendation? = nil
    @Published private(set) var captureStatus: ReplayKitManager.CaptureStatus = .idle

    enum DraftTab: String, CaseIterable { case recommendations, teamAnalysis, strategy, manual }

    // MARK: - Dependencies
    private let draftStateManager: DraftStateManager
    private let recommendationEngine: RecommendationEngine
    private let itemEngine: ItemRecommendationEngine
    private let strategyEngine: StrategyEngine
    private let replayKitManager: ReplayKitManager
    private let visionEngine: VisionEngine

    // MARK: - Subscriptions
    private var cancellables: Set<AnyCancellable> = []
    private var stateTask: Task<Void, Never>?
    private var recommendationTask: Task<Void, Never>?

    init(
        draftStateManager: DraftStateManager,
        recommendationEngine: RecommendationEngine,
        itemEngine: ItemRecommendationEngine,
        strategyEngine: StrategyEngine,
        replayKitManager: ReplayKitManager,
        visionEngine: VisionEngine
    ) {
        self.draftStateManager = draftStateManager
        self.recommendationEngine = recommendationEngine
        self.itemEngine = itemEngine
        self.strategyEngine = strategyEngine
        self.replayKitManager = replayKitManager
        self.visionEngine = visionEngine

        bindDraftState()
        bindCaptureStatus()
    }

    // MARK: - Capture Control

    func startCapture() async {
        captureError = nil
        do {
            let granted = try await replayKitManager.requestPermission()
            guard granted else {
                captureError = "Screen recording permission was denied. Enable it in Settings."
                return
            }
            setupVisionPipeline()
            try await replayKitManager.startCapture()
            draftStateManager.startTracking()
        } catch {
            captureError = error.localizedDescription
        }
    }

    func stopCapture() async {
        await replayKitManager.stopCapture()
        draftStateManager.stopTracking()
    }

    func resetDraft() async {
        await draftStateManager.reset()
        recommendations = []
        topRecommendation = nil
        strategy = nil
        teamAnalysis = TeamCompositionAnalysis()
    }

    // MARK: - Manual Draft Control

    func setPhase(_ phase: DraftPhase) {
        draftStateManager.setPhase(phase)
    }

    func pickHero(_ heroName: String, team: DraftTurn, slot: Int) {
        draftStateManager.manuallySetHero(heroName, team: team, slot: slot, isBan: false)
        regenerateRecommendations()
    }

    func banHero(_ heroName: String, team: DraftTurn, slot: Int) {
        draftStateManager.manuallySetHero(heroName, team: team, slot: slot, isBan: true)
        regenerateRecommendations()
    }

    func clearSlot(team: DraftTurn, slot: Int, isBan: Bool) {
        draftStateManager.clearSlot(team: team, slot: slot, isBan: isBan)
        regenerateRecommendations()
    }

    // MARK: - Private Setup

    private func setupVisionPipeline() {
        replayKitManager.onFrameCaptured = { [weak self] pixelBuffer, timestamp in
            guard let self else { return }
            Task {
                let result = try? await self.visionEngine.processFrame(pixelBuffer, timestamp: timestamp)
                if let result {
                    await self.draftStateManager.update(with: result)
                }
            }
        }
    }

    private func bindDraftState() {
        draftStateManager.$currentDraftState
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in
                guard let self else { return }
                self.draftState = newState
                self.regenerateRecommendations()
            }
            .store(in: &cancellables)
    }

    private func bindCaptureStatus() {
        replayKitManager.$isCapturing
            .receive(on: RunLoop.main)
            .assign(to: &$isCapturing)

        replayKitManager.$captureStatus
            .receive(on: RunLoop.main)
            .assign(to: &$captureStatus)
    }

    private func regenerateRecommendations() {
        recommendationTask?.cancel()
        recommendationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isProcessing = true
            defer { self.isProcessing = false }

            guard !Task.isCancelled else { return }

            do {
                let result = try await recommendationEngine.generateRecommendations(
                    for: draftState,
                    userProfile: nil,
                    limit: 5
                )

                guard !Task.isCancelled else { return }

                withAnimation(.easeInOut(duration: 0.3)) {
                    self.recommendations = result.recommendations
                    self.topRecommendation = result.topPick
                    self.teamAnalysis = result.teamAnalysis
                }

                // Generate strategy for current composition
                await generateStrategy()
            } catch {
                // Fail silently for recommendation errors
            }
        }
    }

    private func generateStrategy() async {
        let heroDatabase = draftStateManager.heroDatabase
        let friendlyNames = draftState.friendlyPicks.compactMap { $0.heroName }
        let enemyNames = draftState.enemyPicks.compactMap { $0.heroName }

        guard !friendlyNames.isEmpty else { return }

        var friendly: [Hero] = []
        var enemy: [Hero] = []

        for name in friendlyNames {
            if let hero = await heroDatabase.hero(byNameFuzzy: name) { friendly.append(hero) }
        }
        for name in enemyNames {
            if let hero = await heroDatabase.hero(byNameFuzzy: name) { enemy.append(hero) }
        }

        strategy = try? await strategyEngine.generateStrategy(
            friendlyHeroes: friendly,
            enemyHeroes: enemy,
            draftState: draftState
        )
    }
}
