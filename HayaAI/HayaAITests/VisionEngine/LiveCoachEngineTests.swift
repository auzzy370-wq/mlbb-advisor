import XCTest
@testable import HayaAI

final class LiveCoachEngineTests: XCTestCase {

    var engine: LiveCoachEngine!
    var heroDatabase: HeroDatabaseService!

    override func setUp() async throws {
        heroDatabase = HeroDatabaseService()
        engine = LiveCoachEngine(heroDatabase: heroDatabase)
    }

    // MARK: - Alert Type Tests

    func testTurtleSpawningAlertFires() async throws {
        var timer = ObjectiveTimer(type: .turtle)
        timer.status = .respawning
        timer.secondsUntilSpawn = 20

        let alerts = await engine.turtleAlerts(for: timer)
        XCTAssertTrue(alerts.contains { $0.type == .turtleSpawning })
    }

    func testTurtleAliveAlertFires() async throws {
        var timer = ObjectiveTimer(type: .turtle)
        timer.status = .alive
        timer.secondsUntilSpawn = 0

        let alerts = await engine.turtleAlerts(for: timer)
        XCTAssertTrue(alerts.contains { $0.type == .turtleAlive })
    }

    func testLordSpawningAlertFires() async throws {
        var timer = ObjectiveTimer(type: .lord)
        timer.status = .respawning
        timer.secondsUntilSpawn = 15

        let alerts = await engine.lordAlerts(for: timer)
        XCTAssertTrue(alerts.contains { $0.type == .lordSpawning })
    }

    func testLordAliveAlertFires() async throws {
        var timer = ObjectiveTimer(type: .lord)
        timer.status = .alive

        let alerts = await engine.lordAlerts(for: timer)
        XCTAssertTrue(alerts.contains { $0.type == .lordAlive })
    }

    func testNoAlertWhenObjectiveDead() async throws {
        var timer = ObjectiveTimer(type: .turtle)
        timer.status = .dead
        timer.secondsUntilSpawn = 200 // far away

        let alerts = await engine.turtleAlerts(for: timer)
        XCTAssertTrue(alerts.isEmpty)
    }

    // MARK: - Kill Advantage Tests

    func testKillAdvantageAlertFires() async throws {
        var state = LiveGameState()
        state.killScore = KillScore(friendly: 10, enemy: 4)
        state.sessionPhase = .midGame
        state.gameTimeSeconds = 600

        let alerts = await engine.evaluate(state: state)
        XCTAssertTrue(alerts.contains { $0.type == .killAdvantage })
    }

    func testNoKillAdvantageAlertWhenEven() async throws {
        var state = LiveGameState()
        state.killScore = KillScore(friendly: 5, enemy: 5)

        let alerts = await engine.evaluate(state: state)
        XCTAssertFalse(alerts.contains { $0.type == .killAdvantage })
    }

    // MARK: - Player Safety Tests

    func testLowHPAlertFires() async throws {
        var state = LiveGameState()
        state.playerState.currentHP = 0.15
        state.playerState.isAlive = true

        let alerts = await engine.evaluate(state: state)
        XCTAssertTrue(alerts.contains { $0.type == .lowHP })
    }

    func testNoLowHPAlertAtFullHP() async throws {
        var state = LiveGameState()
        state.playerState.currentHP = 1.0

        let alerts = await engine.evaluate(state: state)
        XCTAssertFalse(alerts.contains { $0.type == .lowHP })
    }

    // MARK: - Alert Priority Tests

    func testAlertHasCorrectPriority() async throws {
        var timer = ObjectiveTimer(type: .lord)
        timer.status = .alive

        let alerts = await engine.lordAlerts(for: timer)
        let lordAlert = alerts.first { $0.type == .lordAlive }
        XCTAssertEqual(lordAlert?.priority, .critical)
    }

    func testTurtleSpawnAlertPriority() async throws {
        var timer = ObjectiveTimer(type: .turtle)
        timer.status = .respawning
        timer.secondsUntilSpawn = 10

        let alerts = await engine.turtleAlerts(for: timer)
        let alert = alerts.first { $0.type == .turtleSpawning }
        XCTAssertEqual(alert?.priority, .high)
    }

    // MARK: - Alert Content Tests

    func testAlertHasMessage() async throws {
        var timer = ObjectiveTimer(type: .turtle)
        timer.status = .respawning
        timer.secondsUntilSpawn = 25

        let alerts = await engine.turtleAlerts(for: timer)
        let alert = alerts.first { $0.type == .turtleSpawning }
        XCTAssertFalse(alert?.message.isEmpty ?? true)
    }

    func testAlertHasAction() async throws {
        var timer = ObjectiveTimer(type: .lord)
        timer.status = .alive

        let alerts = await engine.lordAlerts(for: timer)
        let alert = alerts.first
        XCTAssertNotNil(alert?.action)
    }

    // MARK: - Death Timer Tests

    func testDeathTimerPushAlertFires() async throws {
        var state = LiveGameState()
        state.killScore = KillScore(friendly: 5, enemy: 2, friendlyDeaths: 1, enemyDeaths: 3)

        let alerts = await engine.evaluate(state: state)
        XCTAssertTrue(alerts.contains { $0.type == .deathTimerPush })
    }
}

// MARK: - Objective Timer Service Tests
final class ObjectiveTimerServiceTests: XCTestCase {

    var service: ObjectiveTimerService!

    override func setUp() {
        service = ObjectiveTimerService()
    }

    func testInitialTurtleStateIsAlive() async {
        let state = await service.currentTurtleTimer()
        XCTAssertEqual(state.status, .alive)
    }

    func testStartTurtleTimerSetsRespawningStatus() async {
        await service.startTurtleTimer(respawnSeconds: 5)
        let timer = await service.currentTurtleTimer()
        XCTAssertEqual(timer.status, .respawning)
        XCTAssertNotNil(timer.secondsUntilSpawn)
    }

    func testRecordTurtleKilledSetsDeadStatus() async {
        await service.recordKilled(objective: .turtle, by: .friendly)
        let timer = await service.currentTurtleTimer()
        XCTAssertEqual(timer.status, .dead)
        XCTAssertEqual(timer.lastKilledBy, .friendly)
    }

    func testRecordLordKilledSetsDeadStatus() async {
        await service.recordKilled(objective: .lord, by: .enemy)
        let timer = await service.currentLordTimer()
        XCTAssertEqual(timer.status, .dead)
        XCTAssertEqual(timer.lastKilledBy, .enemy)
    }

    func testTurtleTimerCountsDown() async throws {
        await service.startTurtleTimer(respawnSeconds: 3)
        try await Task.sleep(nanoseconds: 1_500_000_000) // wait 1.5s
        let timer = await service.currentTurtleTimer()
        let remaining = timer.secondsUntilSpawn ?? 0
        XCTAssertLessThan(remaining, 3)
    }

    func testTurtleSpawnsAfterCountdown() async throws {
        await service.startTurtleTimer(respawnSeconds: 2)
        try await Task.sleep(nanoseconds: 2_500_000_000) // wait 2.5s
        let timer = await service.currentTurtleTimer()
        XCTAssertEqual(timer.status, .alive)
    }

    func testObjectiveTimerPublisherEmits() async throws {
        var receivedStates: [ObjectiveState] = []
        let cancellable = service.objectiveStatePublisher
            .prefix(3)
            .sink { receivedStates.append($0) }

        await service.startTurtleTimer(respawnSeconds: 5)
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertFalse(receivedStates.isEmpty)
        cancellable.cancel()
    }

    func testStopAllCancelsTimers() async throws {
        await service.startTurtleTimer(respawnSeconds: 10)
        await service.startLordTimer(firstSpawnSeconds: 10)
        await service.stopAll()
        // After stop, timers should not continue updating
        let before = await service.currentTurtleTimer().secondsUntilSpawn
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let after = await service.currentTurtleTimer().secondsUntilSpawn
        // They should be equal (frozen) after stopAll
        XCTAssertEqual(before, after)
    }
}

// MARK: - Game State Tests
final class LiveGameStateTests: XCTestCase {

    func testGameTimeFormattedZero() {
        var state = LiveGameState()
        state.gameTimeSeconds = 0
        XCTAssertEqual(state.gameTimeFormatted, "0:00")
    }

    func testGameTimeFormattedMinutes() {
        var state = LiveGameState()
        state.gameTimeSeconds = 8 * 60 + 32
        XCTAssertEqual(state.gameTimeFormatted, "8:32")
    }

    func testKillLeadPositive() {
        var state = LiveGameState()
        state.killScore = KillScore(friendly: 8, enemy: 3)
        XCTAssertEqual(state.killScore.killLead, 5)
        XCTAssertTrue(state.killScore.isAhead)
    }

    func testKillLeadNegative() {
        var state = LiveGameState()
        state.killScore = KillScore(friendly: 2, enemy: 7)
        XCTAssertTrue(state.killScore.isBehind)
        XCTAssertFalse(state.killScore.isAhead)
    }

    func testSessionPhaseEarlyGame() {
        let phase = GameSessionClassifier().detectFromClock(seconds: 180)
        XCTAssertEqual(phase, .earlyGame)
    }

    func testSessionPhaseMidGame() {
        let phase = GameSessionClassifier().detectFromClock(seconds: 600)
        XCTAssertEqual(phase, .midGame)
    }

    func testSessionPhaseLateGame() {
        let phase = GameSessionClassifier().detectFromClock(seconds: 1200)
        XCTAssertEqual(phase, .lateGame)
    }

    func testObjectiveTimerIsAboutToSpawn() {
        var timer = ObjectiveTimer(type: .turtle)
        timer.secondsUntilSpawn = 25
        XCTAssertTrue(timer.isAboutToSpawn)
    }

    func testObjectiveTimerNotAboutToSpawn() {
        var timer = ObjectiveTimer(type: .turtle)
        timer.secondsUntilSpawn = 120
        XCTAssertFalse(timer.isAboutToSpawn)
    }

    func testAlertIsExpired() {
        let alert = CoachAlert(
            id: "test",
            type: .turtleAlive,
            priority: .high,
            message: "test",
            detail: nil,
            action: nil,
            triggeredAt: Date().addingTimeInterval(-60),
            expiresAt: Date().addingTimeInterval(-1)
        )
        XCTAssertTrue(alert.isExpired)
        XCTAssertFalse(alert.isActive)
    }

    func testAlertIsNotExpired() {
        let alert = CoachAlert(
            id: "test",
            type: .turtleAlive,
            priority: .high,
            message: "test",
            detail: nil,
            action: nil,
            triggeredAt: Date(),
            expiresAt: Date().addingTimeInterval(30)
        )
        XCTAssertFalse(alert.isExpired)
        XCTAssertTrue(alert.isActive)
    }
}

// MARK: - Alert Engine Tests
final class AlertEngineTests: XCTestCase {

    var alertEngine: AlertEngine!

    override func setUp() {
        alertEngine = AlertEngine()
    }

    func testFilterRemovesDuplicateTypes() async {
        let existing = [
            CoachAlert(id: "1", type: .turtleAlive, priority: .high, message: "m", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let incoming = [
            CoachAlert(id: "2", type: .turtleAlive, priority: .high, message: "m2", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let result = await alertEngine.filter(incoming, existingAlerts: existing)
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterAllowsNewTypes() async {
        let existing = [
            CoachAlert(id: "1", type: .turtleAlive, priority: .high, message: "m", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let incoming = [
            CoachAlert(id: "2", type: .lordAlive, priority: .critical, message: "m2", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let result = await alertEngine.filter(incoming, existingAlerts: existing)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .lordAlive)
    }

    func testPrioritiseSortsByPriority() async {
        let alerts = [
            CoachAlert(id: "1", type: .turtleSpawning, priority: .medium, message: "", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30)),
            CoachAlert(id: "2", type: .lordAlive, priority: .critical, message: "", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30)),
            CoachAlert(id: "3", type: .enemyMissing, priority: .high, message: "", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let sorted = await alertEngine.prioritise(alerts, limit: 3)
        XCTAssertEqual(sorted.first?.priority, .critical)
        XCTAssertEqual(sorted.last?.priority, .medium)
    }

    func testPurgeExpiredRemovesOldAlerts() async {
        let alerts = [
            CoachAlert(id: "1", type: .turtleAlive, priority: .high, message: "", detail: nil, action: nil,
                       triggeredAt: Date().addingTimeInterval(-60), expiresAt: Date().addingTimeInterval(-1)),
            CoachAlert(id: "2", type: .lordAlive, priority: .critical, message: "", detail: nil, action: nil,
                       triggeredAt: Date(), expiresAt: Date().addingTimeInterval(30))
        ]
        let purged = await alertEngine.purgeExpired(alerts)
        XCTAssertEqual(purged.count, 1)
        XCTAssertEqual(purged.first?.id, "2")
    }
}
