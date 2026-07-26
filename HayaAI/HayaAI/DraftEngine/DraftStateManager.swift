import Foundation
import Combine

// MARK: - Draft State Manager
/// Single source of truth for the current draft state.
/// Consumes FrameAnalysisResults from the Vision Engine and applies
/// them to produce a clean, de-duplicated DraftState.
@MainActor
final class DraftStateManager: ObservableObject, DraftEngineProtocol {

    // MARK: - Published
    @Published private(set) var currentDraftState: DraftState = DraftState()
    @Published private(set) var lastUpdateTime: Date = Date()
    @Published private(set) var isTracking: Bool = false
    @Published private(set) var confidenceLevel: Double = 0.0

    // MARK: - Async Stream
    private var stateContinuation: AsyncStream<DraftState>.Continuation?
    nonisolated var statePublisher: AsyncStream<DraftState> {
        AsyncStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                self?.stateContinuation = continuation
            }
        }
    }

    // MARK: - Dependencies
    let heroDatabase: HeroDatabaseService
    private let changeDetector = StateChangeDetector()
    private let reconciler = DraftStateReconciler()

    // MARK: - Tracking
    private var analysisBuffer: [FrameAnalysisResult] = []
    private let bufferSize = 5

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
    }

    // MARK: - DraftEngineProtocol

    func update(with analysisResult: FrameAnalysisResult) async {
        guard await changeDetector.hasSignificantChange(analysisResult) else { return }

        // Buffer for smoothing
        analysisBuffer.append(analysisResult)
        if analysisBuffer.count > bufferSize { analysisBuffer.removeFirst() }

        let smoothed = smoothedResult(from: analysisBuffer)
        let newState = await reconciler.reconcile(
            current: currentDraftState,
            result: smoothed,
            heroDatabase: heroDatabase
        )

        guard newState != currentDraftState else { return }

        currentDraftState = newState
        lastUpdateTime = Date()
        confidenceLevel = analysisResult.overallConfidence
        stateContinuation?.yield(newState)
    }

    func reset() async {
        currentDraftState = DraftState()
        lastUpdateTime = Date()
        isTracking = false
        confidenceLevel = 0
        analysisBuffer = []
        await changeDetector.reset()
    }

    func setPhase(_ phase: DraftPhase) {
        currentDraftState.phase = phase
        stateContinuation?.yield(currentDraftState)
    }

    func addHeroToPick(_ heroName: String, team: DraftTurn, slot: Int) {
        var picks = team == .friendly ? currentDraftState.friendlyPicks : currentDraftState.enemyPicks
        guard slot < picks.count else { return }
        picks[slot].heroName = heroName
        picks[slot].status = .locked
        if team == .friendly {
            currentDraftState.friendlyPicks = picks
        } else {
            currentDraftState.enemyPicks = picks
        }
        stateContinuation?.yield(currentDraftState)
    }

    func addHeroToBan(_ heroName: String, team: DraftTurn, slot: Int) {
        var bans = team == .friendly ? currentDraftState.friendlyBans : currentDraftState.enemyBans
        guard slot < bans.count else { return }
        bans[slot].heroName = heroName
        bans[slot].status = .banned
        if team == .friendly {
            currentDraftState.friendlyBans = bans
        } else {
            currentDraftState.enemyBans = bans
        }
        stateContinuation?.yield(currentDraftState)
    }

    func setHoveredHero(_ heroName: String?) {
        currentDraftState.hoveredHero = heroName
        stateContinuation?.yield(currentDraftState)
    }

    func setTimer(_ seconds: Int) {
        currentDraftState.timer = seconds
        stateContinuation?.yield(currentDraftState)
    }

    func startTracking() { isTracking = true }
    func stopTracking() { isTracking = false }

    // MARK: - Manual Overrides
    func manuallySetHero(_ heroName: String, team: DraftTurn, slot: Int, isBan: Bool) {
        if isBan {
            addHeroToBan(heroName, team: team, slot: slot)
        } else {
            addHeroToPick(heroName, team: team, slot: slot)
        }
    }

    func clearSlot(team: DraftTurn, slot: Int, isBan: Bool) {
        if isBan {
            var bans = team == .friendly ? currentDraftState.friendlyBans : currentDraftState.enemyBans
            guard slot < bans.count else { return }
            bans[slot] = DraftSlot.empty(team: team, position: slot)
            if team == .friendly { currentDraftState.friendlyBans = bans }
            else { currentDraftState.enemyBans = bans }
        } else {
            var picks = team == .friendly ? currentDraftState.friendlyPicks : currentDraftState.enemyPicks
            guard slot < picks.count else { return }
            picks[slot] = DraftSlot.empty(team: team, position: slot)
            if team == .friendly { currentDraftState.friendlyPicks = picks }
            else { currentDraftState.enemyPicks = picks }
        }
        stateContinuation?.yield(currentDraftState)
    }

    // MARK: - Private Helpers

    private func smoothedResult(from buffer: [FrameAnalysisResult]) -> FrameAnalysisResult {
        guard let latest = buffer.last else {
            fatalError("Buffer must not be empty")
        }
        // Use majority vote for detected phase
        let phaseCounts = Dictionary(grouping: buffer.compactMap { $0.detectedPhase }) { $0 }
        let majorityPhase = phaseCounts.max(by: { $0.value.count < $1.value.count })?.key

        // Use median for timer
        let timers = buffer.compactMap { $0.detectedTimer }.sorted()
        let medianTimer: Int? = timers.isEmpty ? nil : timers[timers.count / 2]

        return FrameAnalysisResult(
            detectedHeroes: latest.detectedHeroes,
            detectedTexts: latest.detectedTexts,
            detectedPhase: majorityPhase ?? latest.detectedPhase,
            detectedTimer: medianTimer ?? latest.detectedTimer,
            detectedTurn: latest.detectedTurn,
            detectedPatch: latest.detectedPatch,
            processingTimeMs: latest.processingTimeMs,
            frameTimestamp: latest.frameTimestamp,
            overallConfidence: buffer.map { $0.overallConfidence }.reduce(0, +) / Double(buffer.count)
        )
    }
}

// MARK: - Draft State Reconciler
/// Merges a FrameAnalysisResult into the existing DraftState.
actor DraftStateReconciler {

    func reconcile(
        current: DraftState,
        result: FrameAnalysisResult,
        heroDatabase: HeroDatabaseService
    ) async -> DraftState {
        var state = current

        if let phase = result.detectedPhase { state.phase = phase }
        if let timer = result.detectedTimer { state.timer = timer }
        if let turn = result.detectedTurn { state.currentTurn = turn }
        if let patch = result.detectedPatch { state.patchVersion = patch }
        state.confidence = result.overallConfidence
        state.detectedAt = Date()

        // Apply hero detections
        let friendlyHeroes = result.detectedHeroes.filter { $0.team == .friendly }
        let enemyHeroes = result.detectedHeroes.filter { $0.team == .enemy }

        for hero in friendlyHeroes where hero.slotIndex < 5 {
            if state.friendlyPicks[hero.slotIndex].heroName == nil ||
               hero.confidence > 0.7 {
                state.friendlyPicks[hero.slotIndex].heroName = hero.name
                state.friendlyPicks[hero.slotIndex].status = .locked
            }
        }

        for hero in enemyHeroes where hero.slotIndex < 5 {
            if state.enemyPicks[hero.slotIndex].heroName == nil ||
               hero.confidence > 0.7 {
                state.enemyPicks[hero.slotIndex].heroName = hero.name
                state.enemyPicks[hero.slotIndex].status = .locked
            }
        }

        // Update available heroes list
        let unavailable = Set(state.unavailableHeroIDs)
        let allNames = await heroDatabase.allHeroNames()
        state.availableHeroes = allNames.filter { !unavailable.contains($0) }

        return state
    }
}
