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

    /// Live OCR engine fed hero names from the database.
    /// Nil only during the brief async init window; assigned before any frame arrives.
    private var ocrEngine: OCREngine?
    /// Throttle: skip OCR if the previous request finished fewer than 1.2 s ago.
    private var lastOCRTime: Date = .distantPast

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

        // Initialise the OCR engine with every hero name in the database so
        // Vision can match hero text found on screen during draft / in-game.
        Task {
            let names = await draftStateManager.heroDatabase.allHeroNames()
            let cfg = OCREngine.Configuration(
                recognitionLevel: .fast,   // fast = ~200 ms/frame vs ~1 s for accurate
                recognitionLanguages: ["en-US"],
                usesLanguageCorrection: false,
                minimumTextHeight: 0.018,
                customWords: names          // prime Vision with all hero names
            )
            ocrEngine = OCREngine(configuration: cfg, heroNames: names)
        }
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

    /// Runs Vision OCR on a broadcast frame and returns a fully-populated
    /// `FrameAnalysisResult` that `DraftStateManager` can reconcile into
    /// the live `DraftState`.
    ///
    /// OCR is throttled to once every 1.2 s so it doesn't starve the UI thread.
    /// We run full-image text recognition and use bounding-box positions to
    /// assign heroes to friendly/enemy sides and approximate slot indices.
    private func inGameAnalysis(from image: CGImage, timestamp: Int) async -> FrameAnalysisResult {
        let emptyResult = FrameAnalysisResult(
            detectedHeroes: [], detectedTexts: [],
            detectedPhase: nil, detectedTimer: nil,
            detectedTurn: nil, detectedPatch: nil,
            processingTimeMs: 0,
            frameTimestamp: CMTimeValue(timestamp),
            overallConfidence: 0
        )

        guard let ocr = ocrEngine else { return emptyResult }

        // Throttle: skip this frame if OCR ran too recently
        let now = Date()
        guard now.timeIntervalSince(lastOCRTime) >= 1.2 else { return emptyResult }
        lastOCRTime = now

        let startTime = now

        // Full-screen text recognition — Vision coordinate origin is bottom-left.
        let allTexts = (try? await ocr.recognizeText(in: image, roi: nil)) ?? []
        guard !allTexts.isEmpty else { return emptyResult }

        var detectedHeroes: [DetectedHero] = []
        var detectedPhase: DraftPhase? = nil
        var detectedTimer: Int? = nil
        var bestConfidence = 0.0

        for text in allTexts where text.confidence > 0.45 {
            bestConfidence = max(bestConfidence, text.confidence)
            let box = text.boundingBox   // normalized, origin bottom-left

            switch text.category {
            case .heroName:
                // Horizontal split: left half = friendly, right half = enemy.
                // This matches the MLBB draft layout in landscape orientation.
                let team: DraftTurn = box.midX < 0.5 ? .friendly : .enemy

                // Vertical slot estimation inside the pick column (approx y=0.15…0.85).
                // Vision y=1.0 is the TOP of the image; heroes are ordered top→bottom.
                let relY = (box.midY - 0.15) / 0.70   // 0=bottom of pick area, 1=top
                let slot = min(4, max(0, Int((1.0 - relY) * 5)))

                detectedHeroes.append(DetectedHero(
                    name: text.text,
                    boundingBox: box,
                    confidence: text.confidence,
                    team: team,
                    slotIndex: slot,
                    detectionMethod: .ocr
                ))

            case .phase:
                let lower = text.text.lowercased()
                if lower.contains("ban")        { detectedPhase = .banPhase1 }
                else if lower.contains("pick")  { detectedPhase = .pickPhase1 }

            case .timer:
                if let v = Int(text.text), v >= 1, v <= 99 { detectedTimer = v }

            default:
                break
            }
        }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1_000
        return FrameAnalysisResult(
            detectedHeroes: detectedHeroes,
            detectedTexts: allTexts,
            detectedPhase: detectedPhase,
            detectedTimer: detectedTimer,
            detectedTurn: nil,
            detectedPatch: nil,
            processingTimeMs: elapsedMs,
            frameTimestamp: CMTimeValue(timestamp),
            overallConfidence: bestConfidence
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
