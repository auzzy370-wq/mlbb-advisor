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

    /// Injected from MainTabView so OCR results flow into the coaching engine.
    weak var gameSessionManager: GameSessionManager?

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
        // Single onFrame handler — routes each broadcast frame to:
        //  1. OCR/draft pipeline (hero names, phase, bans/picks)
        //  2. Coaching pipeline (game clock, kill score → GameSessionManager)
        broadcastFrameReader.onFrame = { [weak self] cgImage, timestamp in
            guard let self else { return }
            Task {
                let analysis = await self.inGameAnalysis(from: cgImage, timestamp: Int(timestamp))
                // Draft board update
                await self.draftStateManager.update(with: analysis)
                // Live coaching update — push clock + kills to coaching engine
                await self.gameSessionManager?.updateLiveData(
                    clockSeconds: analysis.detectedGameClock,
                    killScore: analysis.detectedKillScore
                )
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
            detectedGameClock: nil, detectedKillScore: nil,
            detectedTurn: nil, detectedPatch: nil,
            processingTimeMs: 0,
            frameTimestamp: CMTimeValue(timestamp),
            overallConfidence: 0
        )

        guard let ocr = ocrEngine else { return emptyResult }

        // Throttle: run OCR at most ~1.5fps (0.65s) to balance accuracy vs CPU.
        // Fast enough to catch picks that happen in ~5s windows during draft.
        let now = Date()
        guard now.timeIntervalSince(lastOCRTime) >= 0.65 else { return emptyResult }
        lastOCRTime = now

        let startTime = now

        // Full-screen text recognition — Vision coordinate origin is bottom-left.
        let allTexts = (try? await ocr.recognizeText(in: image, roi: nil)) ?? []
        guard !allTexts.isEmpty else { return emptyResult }

        var detectedHeroes: [DetectedHero] = []
        var detectedPhase: DraftPhase? = nil
        var detectedTimer: Int? = nil
        var detectedGameClock: Int? = nil
        var detectedKillScore: KillScore? = nil
        var bestConfidence = 0.0

        let clockRegex  = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)
        let killsRegex  = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[:/\-]\s*(\d{1,2})"#)

        for text in allTexts where text.confidence > 0.30 {
            bestConfidence = max(bestConfidence, text.confidence)
            let raw = text.text.trimmingCharacters(in: .whitespaces)
            let box = text.boundingBox   // normalized, origin bottom-left

            switch text.category {
            case .heroName:
                let team: DraftTurn = box.midX < 0.5 ? .friendly : .enemy
                let relY = (box.midY - 0.15) / 0.70
                let slot = min(4, max(0, Int((1.0 - relY) * 5)))
                detectedHeroes.append(DetectedHero(
                    name: raw,
                    boundingBox: box,
                    confidence: text.confidence,
                    team: team,
                    slotIndex: slot,
                    detectionMethod: .ocr
                ))

            case .gameClock:
                // Parse MM:SS → total seconds
                let r = NSRange(raw.startIndex..., in: raw)
                if let m = clockRegex?.firstMatch(in: raw, range: r),
                   let mR = Range(m.range(at: 1), in: raw),
                   let sR = Range(m.range(at: 2), in: raw),
                   let mins = Int(raw[mR]), let secs = Int(raw[sR]) {
                    let total = mins * 60 + secs
                    // Only accept plausible in-game times (0-60 min)
                    if total >= 0 && total <= 3600 {
                        detectedGameClock = total
                    }
                }

            case .killScore:
                // Parse "N : M" → KillScore. Top of screen = both teams.
                // Friendly kills on left (box.midX < 0.5), enemy on right.
                let r = NSRange(raw.startIndex..., in: raw)
                if let m = killsRegex?.firstMatch(in: raw, range: r),
                   let aR = Range(m.range(at: 1), in: raw),
                   let bR = Range(m.range(at: 2), in: raw),
                   let a = Int(raw[aR]), let b = Int(raw[bR]) {
                    // MLBB HUD shows friendly : enemy
                    detectedKillScore = KillScore(friendly: a, enemy: b)
                }

            case .phase:
                let lower = raw.lowercased()
                if lower.contains("ban")       { detectedPhase = .banPhase1 }
                else if lower.contains("pick") { detectedPhase = .pickPhase1 }

            case .timer:
                if let v = Int(raw), v >= 1, v <= 99 { detectedTimer = v }

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
            detectedGameClock: detectedGameClock,
            detectedKillScore: detectedKillScore,
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
