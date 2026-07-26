import Foundation
import Combine

// MARK: - Objective Timer Service
/// Maintains countdown timers for Turtle and Lord respawn.
/// Publishes `ObjectiveState` updates to subscribers every second.
actor ObjectiveTimerService {

    // MARK: - State
    private var objectiveState: ObjectiveState = ObjectiveState()

    // MARK: - Timers
    private var turtleTask: Task<Void, Never>? = nil
    private var lordTask: Task<Void, Never>? = nil

    // MARK: - Publisher
    // `nonisolated let` is safe here: PassthroughSubject is a class (reference type)
    // and the binding is immutable, so nonisolated contexts can access the reference.
    nonisolated let stateSubject = PassthroughSubject<ObjectiveState, Never>()
    nonisolated var objectiveStatePublisher: AnyPublisher<ObjectiveState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - MLBB Timing Constants
    private struct MLBBTimings {
        static let turtleRespawn = 90       // seconds after kill
        static let turtleFirstSpawn = 180   // 3:00 min
        static let lordFirstSpawn = 900     // 15:00 min
        static let lordRespawn = 150        // seconds after kill
    }

    // MARK: - Start Timers

    func startTurtleTimer(respawnSeconds: Int = MLBBTimings.turtleFirstSpawn) {
        objectiveState.turtle.status = .respawning
        objectiveState.turtle.respawnAt = Date().addingTimeInterval(TimeInterval(respawnSeconds))
        objectiveState.turtle.secondsUntilSpawn = respawnSeconds

        turtleTask?.cancel()
        turtleTask = Task {
            await runCountdown(
                seconds: respawnSeconds,
                onTick: { [weak self] remaining in
                    guard let self else { return }
                    await self.updateTurtleTimer(remaining: remaining)
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    await self.onTurtleSpawned()
                }
            )
        }
    }

    func startLordTimer(firstSpawnSeconds: Int = MLBBTimings.lordFirstSpawn) {
        objectiveState.lord.status = .respawning
        objectiveState.lord.respawnAt = Date().addingTimeInterval(TimeInterval(firstSpawnSeconds))
        objectiveState.lord.secondsUntilSpawn = firstSpawnSeconds

        lordTask?.cancel()
        lordTask = Task {
            await runCountdown(
                seconds: firstSpawnSeconds,
                onTick: { [weak self] remaining in
                    guard let self else { return }
                    await self.updateLordTimer(remaining: remaining)
                },
                onComplete: { [weak self] in
                    guard let self else { return }
                    await self.onLordSpawned()
                }
            )
        }
    }

    // MARK: - Kill Events

    func recordKilled(objective: Objective, by team: DraftTurn) async {
        switch objective {
        case .turtle:
            objectiveState.turtle.status = .dead
            objectiveState.turtle.lastKilledAt = Date()
            objectiveState.turtle.lastKilledBy = team
            stateSubject.send(objectiveState)
            // Auto-restart respawn timer
            startTurtleTimer(respawnSeconds: MLBBTimings.turtleRespawn)

        case .lord:
            objectiveState.lord.status = .dead
            objectiveState.lord.lastKilledAt = Date()
            objectiveState.lord.lastKilledBy = team
            stateSubject.send(objectiveState)
            startLordTimer(firstSpawnSeconds: MLBBTimings.lordRespawn)

        default:
            break
        }
    }

    // MARK: - Sync from vision detection
    func update(state: LiveGameState) async {
        // Use the game clock to validate our timer estimates
        let clock = state.gameTimeSeconds
        // If Turtle should be alive at this point but we've marked it as respawning, reconcile
        if clock > MLBBTimings.turtleFirstSpawn && objectiveState.turtle.status == .alive
            && objectiveState.turtle.secondsUntilSpawn == nil {
            // Turtle has already spawned but wasn't killed; it's alive on the map
        }
    }

    // MARK: - Stop All
    func stopAll() async {
        turtleTask?.cancel()
        lordTask?.cancel()
        turtleTask = nil
        lordTask = nil
    }

    // MARK: - Accessors
    func currentTurtleTimer() -> ObjectiveTimer { objectiveState.turtle }
    func currentLordTimer() -> ObjectiveTimer { objectiveState.lord }
    func currentState() -> ObjectiveState { objectiveState }

    // MARK: - Private Helpers

    private func updateTurtleTimer(remaining: Int) async {
        objectiveState.turtle.secondsUntilSpawn = remaining
        stateSubject.send(objectiveState)
    }

    private func updateLordTimer(remaining: Int) async {
        objectiveState.lord.secondsUntilSpawn = remaining
        stateSubject.send(objectiveState)
    }

    private func onTurtleSpawned() async {
        objectiveState.turtle.status = .alive
        objectiveState.turtle.secondsUntilSpawn = 0
        objectiveState.turtle.respawnAt = nil
        stateSubject.send(objectiveState)
    }

    private func onLordSpawned() async {
        objectiveState.lord.status = .alive
        objectiveState.lord.secondsUntilSpawn = 0
        objectiveState.lord.respawnAt = nil
        stateSubject.send(objectiveState)
    }

    private func runCountdown(
        seconds: Int,
        onTick: @escaping @Sendable (Int) async -> Void,
        onComplete: @escaping @Sendable () async -> Void
    ) async {
        var remaining = seconds
        while remaining > 0 && !Task.isCancelled {
            await onTick(remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            remaining -= 1
        }
        if !Task.isCancelled {
            await onComplete()
        }
    }
}

// MARK: - Objective Clock View Model (used by UI)
@MainActor
final class ObjectiveClockViewModel: ObservableObject {
    @Published var turtle: ObjectiveTimer = ObjectiveTimer(type: .turtle)
    @Published var lord: ObjectiveTimer = ObjectiveTimer(type: .lord)

    private var cancellables: Set<AnyCancellable> = []

    func bind(to service: ObjectiveTimerService) {
        service.objectiveStatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.turtle = state.turtle
                self?.lord = state.lord
            }
            .store(in: &cancellables)
    }
}
