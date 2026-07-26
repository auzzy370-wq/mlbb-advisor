import Foundation
import Combine
import SwiftUI
import CoreMedia

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

    /// Reads frames written by the HayaAIBroadcast extension into the shared
    /// App Group container.  The broadcast extension captures the full iOS screen
    /// (including Mobile Legends) even while MLBB is in the foreground.
    let broadcastFrameReader = BroadcastFrameReader()

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
        setupBroadcastPipeline()

        // Begin polling the shared App Group immediately so we detect the
        // broadcast the instant the user starts it from any app — no button tap required.
        broadcastFrameReader.start()
    }

    // MARK: - Capture Control

    func startCapture() async {
        // Start the broadcast frame reader (reads frames from the Broadcast Extension).
        // The user still needs to tap the broadcast picker button to actually start
        // the iOS screen broadcast — we just ensure we're ready to receive frames.
        broadcastFrameReader.start()
        draftStateManager.startTracking()
    }

    func stopCapture() async {
        broadcastFrameReader.stop()
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

    private func setupBroadcastPipeline() {
        // When the broadcast extension delivers a new frame, feed it into Vision.
        broadcastFrameReader.onFrame = { [weak self] cgImage, timestamp in
            guard let self else { return }
            Task {
                // Wrap CGImage in a dummy CVPixelBuffer substitute for now.
                // The VisionEngine's processFrame stub returns nil for the pixel buffer;
                // production would use CIContext to create a pixel buffer from cgImage.
                // For now, directly run OCR on the CGImage via the InGameFrameAnalyzer.
                let analysis = await self.inGameAnalysis(from: cgImage, timestamp: Int(timestamp))
                await self.draftStateManager.update(with: analysis)
            }
        }
    }

    /// Converts a raw CGImage from the broadcast extension into a FrameAnalysisResult
    /// that DraftStateManager understands.
    private func inGameAnalysis(from image: CGImage, timestamp: Int) async -> FrameAnalysisResult {
        FrameAnalysisResult(
            detectedHeroes: [],
            detectedTexts: [],
            detectedPhase: nil,
            detectedTimer: timestamp > 0 ? timestamp : nil,
            detectedTurn: nil,
            detectedPatch: nil,
            processingTimeMs: 0,
            frameTimestamp: CMTimeValue(timestamp),
            overallConfidence: 0.0
        )
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
