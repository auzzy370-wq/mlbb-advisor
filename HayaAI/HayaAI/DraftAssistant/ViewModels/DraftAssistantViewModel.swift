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

    /// Live OCR engine used for in-game text only (clock, kills, phase banners).
    /// MLBB draft uses portrait images — OCR cannot detect hero names during draft.
    private var ocrEngine: OCREngine?
    /// Throttle: skip OCR if the previous request finished fewer than 0.65 s ago.
    private var lastOCRTime: Date = .distantPast

    /// Vision-based hero portrait matcher.
    /// Uses VNFeaturePrint to compare draft-slot crops against cached hero portraits.
    private let portraitMatcher = HeroPortraitMatcher()
    /// Throttle: portrait matching runs every 2 s (more expensive than OCR).
    private var lastPortraitMatchTime: Date = .distantPast

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

        // Initialise the OCR engine for in-game text (clock, kill score, phase banner).
        // Portrait matching (for draft hero detection) uses HeroPortraitMatcher below.
        Task {
            let names = await draftStateManager.heroDatabase.allHeroNames()
            let cfg = OCREngine.Configuration(
                recognitionLevel: .fast,
                recognitionLanguages: ["en-US"],
                usesLanguageCorrection: false,
                minimumTextHeight: 0.018,
                customWords: names
            )
            ocrEngine = OCREngine(configuration: cfg, heroNames: names)

            // Prepare VNFeaturePrint cache for portrait-based hero detection.
            // Downloads 130 tiny thumbnails in the background on first launch; instant on repeat.
            await portraitMatcher.prepare(heroNames: names)
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
        broadcastFrameReader.onFrame = { [weak self] cgImage, timestamp in
            guard let self else { return }
            Task {
                // Run OCR for in-game text (clock/kills) and portrait matching in parallel.
                async let ocrTask = self.inGameAnalysis(from: cgImage, timestamp: Int(timestamp))
                async let portraitTask = self.runPortraitMatchingIfNeeded(frame: cgImage)

                let (analysis, portraitHeroes) = await (ocrTask, portraitTask)

                // Merge portrait-detected heroes into the analysis result, then update draft state.
                let merged = self.mergePortraitHeroes(portraitHeroes, into: analysis, timestamp: timestamp)
                await self.draftStateManager.update(with: merged)

                // Forward live data to coaching engine.
                await self.gameSessionManager?.updateLiveData(
                    clockSeconds: analysis.detectedGameClock,
                    killScore: analysis.detectedKillScore
                )
            }
        }
    }

    /// Runs VNFeaturePrint portrait matching at most every 2 s.
    /// Returns (friendly [0-4], enemy [0-4]) name arrays; nil = empty slot.
    private func runPortraitMatchingIfNeeded(frame: CGImage) async -> (friendly: [String?], enemy: [String?])? {
        let now = Date()
        guard now.timeIntervalSince(lastPortraitMatchTime) >= 2.0 else { return nil }
        lastPortraitMatchTime = now
        return await portraitMatcher.matchDraftSlots(in: frame)
    }

    /// Folds portrait-detected hero names into a `FrameAnalysisResult` as `DetectedHero` entries
    /// so `DraftStateManager` can reconcile them the same way it handles OCR-detected heroes.
    private func mergePortraitHeroes(
        _ portrait: (friendly: [String?], enemy: [String?])?,
        into result: FrameAnalysisResult,
        timestamp: TimeInterval
    ) -> FrameAnalysisResult {
        guard let p = portrait else { return result }

        var extra: [DetectedHero] = []
        for (slot, name) in p.friendly.enumerated() {
            if let n = name {
                extra.append(DetectedHero(
                    name: n,
                    boundingBox: .zero,
                    confidence: 0.70,
                    team: .friendly,
                    slotIndex: slot,
                    detectionMethod: .featurePrint
                ))
            }
        }
        for (slot, name) in p.enemy.enumerated() {
            if let n = name {
                extra.append(DetectedHero(
                    name: n,
                    boundingBox: .zero,
                    confidence: 0.70,
                    team: .enemy,
                    slotIndex: slot,
                    detectionMethod: .featurePrint
                ))
            }
        }
        if extra.isEmpty { return result }

        return FrameAnalysisResult(
            detectedHeroes: result.detectedHeroes + extra,
            detectedTexts: result.detectedTexts,
            detectedPhase: result.detectedPhase,
            detectedTimer: result.detectedTimer,
            detectedGameClock: result.detectedGameClock,
            detectedKillScore: result.detectedKillScore,
            detectedTurn: result.detectedTurn,
            detectedPatch: result.detectedPatch,
            processingTimeMs: result.processingTimeMs,
            frameTimestamp: CMTimeValue(timestamp),
            overallConfidence: max(result.overallConfidence, 0.70)
        )
    }

    /// Runs Vision OCR on a broadcast frame to extract **in-game text only**
    /// (game clock, kill score, phase banner, timer countdown).
    ///
    /// IMPORTANT: MLBB's draft screen shows hero PORTRAIT IMAGES — not text names.
    /// OCR cannot detect heroes from portraits. Draft picks must be entered manually
    /// via the HeroPickerSheet (tap any slot on the draft board).
    ///
    /// OCR is throttled to 1 run per 0.65 s to balance accuracy vs CPU load.
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

        let now = Date()
        guard now.timeIntervalSince(lastOCRTime) >= 0.65 else { return emptyResult }
        lastOCRTime = now
        let startTime = now

        // Run Vision OCR — we only care about numbers and short text here.
        let allTexts = (try? await ocr.recognizeText(in: image, roi: nil)) ?? []
        guard !allTexts.isEmpty else { return emptyResult }

        var detectedPhase: DraftPhase? = nil
        var detectedTimer: Int? = nil
        var detectedGameClock: Int? = nil
        var detectedKillScore: KillScore? = nil
        var bestConfidence = 0.0

        let clockRegex = try? NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)
        let killsRegex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[:/\-]\s*(\d{1,2})"#)

        for text in allTexts where text.confidence > 0.30 {
            bestConfidence = max(bestConfidence, text.confidence)
            let raw = text.text.trimmingCharacters(in: .whitespaces)

            switch text.category {
            case .gameClock:
                let r = NSRange(raw.startIndex..., in: raw)
                if let m = clockRegex?.firstMatch(in: raw, range: r),
                   let mR = Range(m.range(at: 1), in: raw),
                   let sR = Range(m.range(at: 2), in: raw),
                   let mins = Int(raw[mR]), let secs = Int(raw[sR]) {
                    let total = mins * 60 + secs
                    if total >= 0 && total <= 3600 { detectedGameClock = total }
                }

            case .killScore:
                let r = NSRange(raw.startIndex..., in: raw)
                if let m = killsRegex?.firstMatch(in: raw, range: r),
                   let aR = Range(m.range(at: 1), in: raw),
                   let bR = Range(m.range(at: 2), in: raw),
                   let a = Int(raw[aR]), let b = Int(raw[bR]) {
                    detectedKillScore = KillScore(friendly: a, enemy: b)
                }

            case .phase:
                let lower = raw.lowercased()
                if lower.contains("ban")       { detectedPhase = .banPhase1 }
                else if lower.contains("pick") { detectedPhase = .pickPhase1 }

            case .timer:
                if let v = Int(raw), v >= 1, v <= 99 { detectedTimer = v }

            // heroName: SKIPPED — MLBB draft uses portrait images, not text.
            // Use the HeroPickerSheet (tap a slot) to add draft picks manually.
            default:
                break
            }
        }

        let elapsedMs = Date().timeIntervalSince(startTime) * 1_000
        return FrameAnalysisResult(
            detectedHeroes: [],          // always empty — no OCR hero detection
            detectedTexts: allTexts,
            detectedPhase: detectedPhase,
            detectedTimer: detectedTimer,
            detectedGameClock: detectedGameClock,
            detectedKillScore: detectedKillScore,
            detectedTurn: nil, detectedPatch: nil,
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
