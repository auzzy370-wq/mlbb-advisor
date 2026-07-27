import Foundation
import Combine
import CoreGraphics
import CoreMedia

// MARK: - Game Session Manager
/// Owns the full lifecycle of one game session: Draft → Loading → In-Game → Post-Game.
/// Bridges the ReplayKit frame stream to both the DraftStateManager (during draft)
/// and the InGameFrameAnalyzer (during live play), switching automatically based on
/// visual phase detection.
@MainActor
final class GameSessionManager: ObservableObject {

    // MARK: - Published State
    @Published private(set) var sessionPhase: GameSessionPhase = .idle
    @Published private(set) var liveGameState: LiveGameState = LiveGameState()
    @Published private(set) var isActive: Bool = false
    @Published private(set) var frameCount: Int = 0

    // MARK: - Dependencies
    let replayKitManager: ReplayKitManager
    let draftStateManager: DraftStateManager
    private let inGameAnalyzer: InGameFrameAnalyzer
    private let objectiveTimerService: ObjectiveTimerService
    let liveCoachEngine: LiveCoachEngine
    private let alertEngine: AlertEngine

    // MARK: - Combine
    private var cancellables: Set<AnyCancellable> = []
    private var objectiveTimerCancellable: AnyCancellable?

    // MARK: - Phase Transition
    private var consecutiveInGameFrames: Int = 0
    private let phaseTransitionThreshold = 10   // 10 consecutive frames to confirm phase change

    init(
        replayKitManager: ReplayKitManager,
        draftStateManager: DraftStateManager,
        heroDatabase: HeroDatabaseService
    ) {
        self.replayKitManager = replayKitManager
        self.draftStateManager = draftStateManager
        self.inGameAnalyzer = InGameFrameAnalyzer()
        self.objectiveTimerService = ObjectiveTimerService()
        self.liveCoachEngine = LiveCoachEngine(heroDatabase: heroDatabase)
        self.alertEngine = AlertEngine()

        bindObjectiveTimers()
    }

    // MARK: - Session Control

    func startSession() async throws {
        guard !isActive else { return }
        isActive = true
        sessionPhase = .draft
        liveGameState.sessionPhase = .draft
        draftStateManager.startTracking()
        // ReplayKit in-app capture is a stub; real frames arrive via routeBroadcastFrame
    }

    /// Called by MainTabView for every frame from the Broadcast Extension.
    /// This is the primary frame ingestion path — no CVPixelBuffer required.
    func routeBroadcastFrame(_ image: CGImage, timestamp: TimeInterval) async {
        guard isActive else { return }
        frameCount += 1

        let cmTimestamp = CMTimeValue(timestamp * 1_000)

        if sessionPhase == .draft || sessionPhase == .loading || sessionPhase == .idle {
            let analysis = await inGameAnalyzer.analyze(image, timestamp: cmTimestamp)
            if let clock = analysis.gameTimestamp, clock > 0 {
                await transitionToGame(at: clock)
            } else if frameCount >= 20 {
                // User is already in-game (broadcast started mid-match and OCR
                // hasn't detected the clock yet). Force-transition so the coaching
                // engine starts evaluating immediately.
                await transitionToGame(at: 0, forced: true)
            }
            return
        }

        guard sessionPhase.isInGame else { return }
        let analysis = await inGameAnalyzer.analyze(image, timestamp: cmTimestamp)
        await applyInGameAnalysis(analysis)
    }

    func endSession() async {
        await replayKitManager.stopCapture()
        draftStateManager.stopTracking()
        await objectiveTimerService.stopAll()
        isActive = false
        sessionPhase = .idle
    }

    // MARK: - Frame Routing
    /// Decides whether a frame belongs to draft processing or in-game processing
    /// based on the current session phase and visual cues.
    private func routeFrame(_ pixelBuffer: CVPixelBufferRef, timestamp: CMTimeValue) async {
        frameCount += 1

        // While in draft, keep feeding the draft vision engine
        if sessionPhase == .draft || sessionPhase == .loading {
            // Cheap game-start detection: if we detect a game clock the match has started
            if let cgImage = pixelBufferToCGImage(pixelBuffer) {
                let analysis = await inGameAnalyzer.analyze(cgImage, timestamp: timestamp)
                if let clock = analysis.gameTimestamp, clock > 0 {
                    await transitionToGame(at: clock)
                }
            }
            return
        }

        // In-game: run the live analyzer
        guard sessionPhase.isInGame, let cgImage = pixelBufferToCGImage(pixelBuffer) else { return }

        let analysis = await inGameAnalyzer.analyze(cgImage, timestamp: timestamp)
        await applyInGameAnalysis(analysis)
    }

    // MARK: - Apply In-Game Analysis
    private func applyInGameAnalysis(_ analysis: InGameFrameAnalysis) async {
        var state = liveGameState
        state.lastFrameProcessedAt = Date()
        state.sessionPhase = analysis.sessionPhase

        if let clock = analysis.gameTimestamp {
            state.gameTimeSeconds = clock
            state.sessionPhase = GameSessionClassifier().detectFromClock(seconds: clock)
        }
        if let kills = analysis.killScoreDetected {
            state.killScore = kills
        }
        if let economy = analysis.goldDetected {
            state.economy = EconomyState(
                friendlyGold: economy.friendlyGold,
                enemyGold: state.economy.enemyGold
            )
        }
        if let hp = analysis.playerHP { state.playerState.currentHP = hp }
        if let mana = analysis.playerMana { state.playerState.currentMana = mana }
        state.minimap.detectedEnemyPositions = analysis.enemyPositions
        state.minimap.lastUpdatedAt = Date()

        // Run coaching pass
        let alerts = await liveCoachEngine.evaluate(state: state)
        let dedupedAlerts = await alertEngine.filter(alerts, existingAlerts: state.activeAlerts)
        state.activeAlerts = (state.activeAlerts.filter { $0.isActive } + dedupedAlerts)
            .sorted { $0.priority > $1.priority }
            .prefix(5)
            .map { $0 }

        // Update objective timers with current state
        await objectiveTimerService.update(state: state)

        liveGameState = state
        sessionPhase = state.sessionPhase
    }

    // MARK: - Phase Transitions

    private func transitionToGame(at clock: Int, forced: Bool = false) async {
        guard sessionPhase != .earlyGame && sessionPhase != .midGame && sessionPhase != .lateGame else { return }

        if forced {
            consecutiveInGameFrames = phaseTransitionThreshold  // skip threshold
        } else {
            consecutiveInGameFrames += 1
        }
        guard consecutiveInGameFrames >= phaseTransitionThreshold else { return }
        consecutiveInGameFrames = 0

        let phase = GameSessionClassifier().detectFromClock(seconds: clock > 0 ? clock : nil)
        sessionPhase = phase
        liveGameState.sessionPhase = phase
        draftStateManager.stopTracking()

        // Start objective timers (offset by detected clock if available)
        let turtleFirst = clock > 0 ? max(1, 240 - clock) : 240
        let lordFirst   = clock > 0 ? max(1, 900 - clock) : 900
        await objectiveTimerService.startTurtleTimer(respawnSeconds: turtleFirst)
        await objectiveTimerService.startLordTimer(firstSpawnSeconds: lordFirst)
    }

    // MARK: - Objective Timer Binding
    private func bindObjectiveTimers() {
        objectiveTimerService.objectiveStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] objectiveState in
                guard let self else { return }
                self.liveGameState.objectives = objectiveState
                Task { await self.checkObjectiveAlerts(objectiveState) }
            }
            .store(in: &cancellables)
    }

    private func checkObjectiveAlerts(_ state: ObjectiveState) async {
        // Generate objective alerts and push them into the alert engine
        let turtleAlerts = await liveCoachEngine.turtleAlerts(for: state.turtle)
        let lordAlerts = await liveCoachEngine.lordAlerts(for: state.lord)
        let newAlerts = turtleAlerts + lordAlerts
        let filtered = await alertEngine.filter(newAlerts, existingAlerts: liveGameState.activeAlerts)
        liveGameState.activeAlerts = (liveGameState.activeAlerts.filter { $0.isActive } + filtered)
            .sorted { $0.priority > $1.priority }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Live data feed from OCR pipeline
    /// Called by DraftAssistantViewModel after each OCR pass with the extracted
    /// game clock and kill score. This is the primary way real game data enters
    /// the coaching engine from broadcast frames.
    func updateLiveData(clockSeconds: Int?, killScore: KillScore?) async {
        var didChange = false

        if let clock = clockSeconds, clock > 0 {
            if liveGameState.gameTimeSeconds != clock {
                liveGameState.gameTimeSeconds = clock
                let phase = GameSessionClassifier().detectFromClock(seconds: clock)
                if phase != liveGameState.sessionPhase {
                    liveGameState.sessionPhase = phase
                    sessionPhase = phase
                }
                didChange = true
            }
            // Ensure session is marked active and in-game
            if !isActive {
                isActive = true
                await objectiveTimerService.startTurtleTimer(respawnSeconds: max(1, 240 - clock))
                await objectiveTimerService.startLordTimer(firstSpawnSeconds: max(1, 900 - clock))
            }
            if sessionPhase == .draft || sessionPhase == .loading || sessionPhase == .idle {
                await transitionToGame(at: clock, forced: true)
            }
        }

        if let ks = killScore {
            liveGameState.killScore = ks
            didChange = true
        }

        // Run a coaching pass whenever data changes
        if didChange {
            let alerts = await liveCoachEngine.evaluate(state: liveGameState)
            let deduped = await alertEngine.filter(alerts, existingAlerts: liveGameState.activeAlerts)
            liveGameState.activeAlerts = (liveGameState.activeAlerts.filter { $0.isActive } + deduped)
                .sorted { $0.priority > $1.priority }
                .prefix(5)
                .map { $0 }
        }
    }

    // MARK: - Manual Controls (for when auto-detection is imperfect)
    func manuallySetPhase(_ phase: GameSessionPhase) {
        sessionPhase = phase
        liveGameState.sessionPhase = phase
    }

    func recordObjectiveKilled(_ objective: Objective, by team: DraftTurn) async {
        await objectiveTimerService.recordKilled(objective: objective, by: team)
    }

    func dismissAlert(id: String) {
        liveGameState.activeAlerts = liveGameState.activeAlerts.map {
            var a = $0; if a.id == id { a.hasBeenDismissed = true }; return a
        }
    }

    // MARK: - Pixel Buffer Conversion
    private func pixelBufferToCGImage(_ buffer: CVPixelBufferRef) -> CGImage? {
        // Production: use CIImage(cvPixelBuffer:) → CIContext.createCGImage
        return nil
    }
}
