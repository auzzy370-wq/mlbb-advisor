import Foundation

// MARK: - Live Coach Engine
/// The brain of the in-game coaching system.
/// Evaluates the current `LiveGameState` and emits `CoachAlert` objects
/// covering objectives, rotations, kills, ganks, and strategy.
/// All logic is rule-based and runs in < 10ms per frame.
actor LiveCoachEngine {

    private let heroDatabase: HeroDatabaseService
    private let tacticalAdvisor: TacticalAdvisor

    // Cooldowns prevent spamming the same alert (alert type → next allowed fire time)
    private var alertCooldowns: [AlertType: Date] = [:]

    // Default cooldown durations per alert type
    private let cooldownSeconds: [AlertType: Double] = [
        .turtleSpawning:     20,
        .turtleAlive:        30,
        .lordSpawning:       20,
        .lordAlive:          30,
        .enemyMissing:       15,
        .gankRisk:           20,
        .killAdvantage:      45,
        .goldAdvantage:      60,
        .pushOpportunity:    30,
        .rotateNow:          25,
        .baseRace:           10,
        .deathTimerPush:     20,
        .lowHP:              10,
        .backOff:            15,
        .groupUp:            30,
        .splitPush:          45,
        .firstBloodChance:   60,
        .powerSpikeReached:  120,
        .rotateToTurtle:     30,
        .enemyGrouping:      20,
        .objectiveStolenRisk: 15,
        .teamfightStarting:  10,
        .enemyInvisible:     20,
        .gameOver:           9999
    ]

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.tacticalAdvisor = TacticalAdvisor()
    }

    // MARK: - Main Evaluation

    func evaluate(state: LiveGameState) async -> [CoachAlert] {
        var alerts: [CoachAlert] = []

        alerts += evaluateObjectives(state)
        alerts += evaluateEnemyPositions(state)
        alerts += evaluateKillAdvantage(state)
        alerts += evaluateRotation(state)
        alerts += evaluatePlayerSafety(state)
        alerts += evaluateDeathTimers(state)
        alerts += evaluatePowerSpike(state)
        alerts += evaluateTeamfight(state)

        return alerts.filter { canFire($0.type) }
    }

    // MARK: - Specific Alert Generators

    // Objective alerts
    func turtleAlerts(for timer: ObjectiveTimer) async -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        if let secs = timer.secondsUntilSpawn {
            if secs <= 30 && secs > 0 && canFire(.turtleSpawning) {
                alerts.append(makeAlert(
                    type: .turtleSpawning,
                    priority: .high,
                    message: "Turtle spawning in \(secs)s!",
                    detail: "Group up and contest. Set vision in the bush at the turtle pit now.",
                    action: "Rotate to Turtle"
                ))
            } else if secs <= 60 && secs > 30 && canFire(.rotateToTurtle) {
                alerts.append(makeAlert(
                    type: .rotateToTurtle,
                    priority: .medium,
                    message: "Rotate to Turtle soon",
                    detail: "Turtle spawns in \(secs)s. Start grouping mid and place vision.",
                    action: "Start rotating"
                ))
            }
        }
        if timer.status == .alive && canFire(.turtleAlive) {
            alerts.append(makeAlert(
                type: .turtleAlive,
                priority: .high,
                message: "Turtle is alive — contest now!",
                detail: "Do NOT let the enemy take free Turtle. Your team should be grouped.",
                action: "Fight for Turtle"
            ))
        }
        return alerts
    }

    func lordAlerts(for timer: ObjectiveTimer) async -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        if let secs = timer.secondsUntilSpawn {
            if secs <= 30 && secs > 0 && canFire(.lordSpawning) {
                alerts.append(makeAlert(
                    type: .lordSpawning,
                    priority: .critical,
                    message: "LORD spawns in \(secs)s!",
                    detail: "This is the most important objective. All 5 must group. Contest even if behind.",
                    action: "Group for Lord NOW"
                ))
            } else if secs <= 60 && secs > 30 && canFire(.lordAlive) {
                alerts.append(makeAlert(
                    type: .lordAlive,
                    priority: .high,
                    message: "Lord spawning in \(secs)s",
                    detail: "Finish your current fight or rotation and prepare to group for Lord.",
                    action: "Prepare for Lord"
                ))
            }
        }
        if timer.status == .alive && canFire(.lordAlive) {
            alerts.append(makeAlert(
                type: .lordAlive,
                priority: .critical,
                message: "LORD is alive — fight NOW!",
                detail: "Lord can win the game. All 5 group and contest regardless of gold lead.",
                action: "Take Lord"
            ))
        }
        return alerts
    }

    // MARK: - Private Rule Evaluators

    private func evaluateObjectives(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        let turtle = state.objectives.turtle
        let lord = state.objectives.lord

        // Warn when objective is about to respawn and enemies might steal it
        if let secs = turtle.secondsUntilSpawn, secs <= 20, canFire(.objectiveStolenRisk) {
            if state.minimap.detectedEnemyPositions.count > 2 {
                alerts.append(makeAlert(
                    type: .objectiveStolenRisk,
                    priority: .critical,
                    message: "Enemy may steal Turtle!",
                    detail: "\(state.minimap.detectedEnemyPositions.count) enemies detected near pit. Contest or zone.",
                    action: "Zone or fight"
                ))
            }
        }
        return alerts
    }

    private func evaluateEnemyPositions(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        let missing = state.minimap.missingEnemies

        if missing.count >= 3 && canFire(.enemyMissing) {
            alerts.append(makeAlert(
                type: .enemyMissing,
                priority: .high,
                message: "\(missing.count) enemies missing from map!",
                detail: "Play safe and ward key bushes. Likely setting up for Turtle, gank, or Lord.",
                action: "Play safe — ward up"
            ))
        } else if missing.count >= 2 && canFire(.gankRisk) {
            alerts.append(makeAlert(
                type: .gankRisk,
                priority: .medium,
                message: "Potential gank risk — 2 enemies MIA",
                detail: "Check your minimap and retreat to a safer position. Don't overextend.",
                action: "Back off slightly"
            ))
        }

        // Enemy grouping = teamfight incoming
        let nearMid = state.minimap.detectedEnemyPositions.filter {
            abs($0.normalizedPosition.x - 0.5) < 0.2
        }.count
        if nearMid >= 3 && canFire(.enemyGrouping) {
            alerts.append(makeAlert(
                type: .enemyGrouping,
                priority: .high,
                message: "Enemy grouping mid — teamfight incoming",
                detail: "Your team should group to match. Don't fight alone. Wait for your tank.",
                action: "Group immediately"
            ))
        }

        return alerts
    }

    private func evaluateKillAdvantage(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        let lead = state.killScore.killLead

        if lead >= 5 && canFire(.killAdvantage) {
            alerts.append(makeAlert(
                type: .killAdvantage,
                priority: .high,
                message: "+\(lead) kill lead — snowball now!",
                detail: "Use your gold and item advantage to take towers and Turtle. Don't let the lead drain.",
                action: "Push towers & objectives"
            ))
        }

        if lead >= 3 && canFire(.pushOpportunity) {
            let towersAlive = state.objectives.enemyTowers.filter { $0.isAlive }.count
            if towersAlive > 0 {
                alerts.append(makeAlert(
                    type: .pushOpportunity,
                    priority: .medium,
                    message: "Kill lead — push enemy towers",
                    detail: "Convert your kill advantage into structural damage. Aim for the outer towers.",
                    action: "Take mid/exp tower"
                ))
            }
        }

        if state.economy.isGoldAhead && canFire(.goldAdvantage) {
            alerts.append(makeAlert(
                type: .goldAdvantage,
                priority: .medium,
                message: "Gold lead — your team has the edge",
                detail: "Use your item advantage in teamfights. Force engagements when your carries are strong.",
                action: "Force a fight"
            ))
        }

        return alerts
    }

    private func evaluateRotation(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        let clock = state.gameTimeSeconds

        // Early Turtle window: 3:00 – 5:00
        if (180...300).contains(clock) && state.objectives.turtle.status == .alive && canFire(.rotateToTurtle) {
            alerts.append(makeAlert(
                type: .rotateToTurtle,
                priority: .high,
                message: "Turtle window open! (\(state.gameTimeFormatted))",
                detail: "Group all 5 and contest Turtle. It gives critical gold and XP to your team.",
                action: "Rotate to Turtle pit"
            ))
        }

        // Mid-game grouping (8–12 min)
        if (480...720).contains(clock) && canFire(.groupUp) {
            alerts.append(makeAlert(
                type: .groupUp,
                priority: .medium,
                message: "Mid-game — time to group",
                detail: "Solo laning is less effective now. Group for Turtle and tower sieges.",
                action: "Group mid lane"
            ))
        }

        // Lord window: after 15:00
        if clock > 900 && state.objectives.lord.status == .alive && canFire(.lordAlive) {
            alerts.append(makeAlert(
                type: .lordAlive,
                priority: .critical,
                message: "Lord is up! Group now!",
                detail: "Lord is the strongest objective in the game. Taking it forces a push that can end the match.",
                action: "Fight for Lord"
            ))
        }

        return alerts
    }

    private func evaluatePlayerSafety(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []

        if state.playerState.currentHP < 0.2 && state.playerState.isAlive && canFire(.lowHP) {
            alerts.append(makeAlert(
                type: .lowHP,
                priority: .critical,
                message: "LOW HP — get out now!",
                detail: "You are at critical HP. Retreat to base or use Healing spell immediately.",
                action: "Recall / retreat"
            ))
        } else if state.playerState.currentHP < 0.35 && canFire(.backOff) {
            alerts.append(makeAlert(
                type: .backOff,
                priority: .high,
                message: "Low HP — back off",
                detail: "You are vulnerable. Enemies may chase. Don't extend further into enemy territory.",
                action: "Back to safety"
            ))
        }

        return alerts
    }

    private func evaluateDeathTimers(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        // Count dead enemies (detected via kill score delta)
        // If multiple enemies are dead, this is a push window
        let enemyDeaths = state.killScore.enemyDeaths
        let friendlyDeaths = state.killScore.friendlyDeaths

        // More enemies dead = push now
        if enemyDeaths > friendlyDeaths + 1 && canFire(.deathTimerPush) {
            alerts.append(makeAlert(
                type: .deathTimerPush,
                priority: .high,
                message: "Enemies are dead — push NOW!",
                detail: "Multiple enemies are respawning. Use this death-timer window to take towers or Turtle.",
                action: "Push immediately"
            ))
        }

        return alerts
    }

    private func evaluatePowerSpike(_ state: LiveGameState) -> [CoachAlert] {
        // Power spikes are tracked via hero database for the player's hero
        // In MVP, use a heuristic based on game time and economy
        var alerts: [CoachAlert] = []
        if state.economy.isGoldAhead && state.gameTimeSeconds > 600 && canFire(.powerSpikeReached) {
            alerts.append(makeAlert(
                type: .powerSpikeReached,
                priority: .medium,
                message: "Power spike reached!",
                detail: "Your build is coming online. Now is a great time to force fights and objectives.",
                action: "Engage aggressively"
            ))
        }
        return alerts
    }

    private func evaluateTeamfight(_ state: LiveGameState) -> [CoachAlert] {
        var alerts: [CoachAlert] = []
        let grouped = state.minimap.detectedEnemyPositions.count >= 4
        if grouped && canFire(.teamfightStarting) {
            alerts.append(makeAlert(
                type: .teamfightStarting,
                priority: .high,
                message: "Full team fight incoming!",
                detail: "All or most enemies detected together. Make sure your team is grouped and ultimates are ready.",
                action: "Prepare ultimates"
            ))
        }
        return alerts
    }

    // MARK: - Cooldown Management

    private func canFire(_ type: AlertType) -> Bool {
        guard let lastFired = alertCooldowns[type] else { return true }
        let cooldown = cooldownSeconds[type] ?? 30
        return Date().timeIntervalSince(lastFired) >= cooldown
    }

    private func recordFired(_ type: AlertType) {
        alertCooldowns[type] = Date()
    }

    // MARK: - Alert Factory

    private func makeAlert(
        type: AlertType,
        priority: AlertPriority,
        message: String,
        detail: String? = nil,
        action: String? = nil,
        duration: TimeInterval = 25
    ) -> CoachAlert {
        recordFired(type)
        return CoachAlert(
            id: "\(type.rawValue)-\(Date().timeIntervalSince1970)",
            type: type,
            priority: priority,
            message: message,
            detail: detail,
            action: action,
            triggeredAt: Date(),
            expiresAt: Date().addingTimeInterval(duration)
        )
    }

    // MARK: - Advice text for current phase

    func currentPhaseAdvice(state: LiveGameState) async -> String {
        return await tacticalAdvisor.advice(for: state)
    }
}
