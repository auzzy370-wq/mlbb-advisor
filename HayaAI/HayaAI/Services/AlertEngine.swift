import Foundation

// MARK: - Alert Engine
/// Deduplicates, prioritises, and rate-limits `CoachAlert` objects before
/// they are inserted into `LiveGameState.activeAlerts`.
actor AlertEngine {

    /// Returns only alerts that are new (not already active for the same type).
    func filter(_ incoming: [CoachAlert], existingAlerts: [CoachAlert]) async -> [CoachAlert] {
        let activeTypes = Set(existingAlerts.filter { $0.isActive }.map { $0.type })
        return incoming.filter { !activeTypes.contains($0.type) }
    }

    /// Sort alerts by priority descending, keep top N.
    func prioritise(_ alerts: [CoachAlert], limit: Int = 5) async -> [CoachAlert] {
        Array(alerts
            .filter { $0.isActive }
            .sorted { $0.priority > $1.priority }
            .prefix(limit))
    }

    /// Expire old alerts and return the cleaned list.
    func purgeExpired(_ alerts: [CoachAlert]) async -> [CoachAlert] {
        alerts.filter { $0.isActive }
    }

    /// Insert a new alert, removing any existing alert of the same type first.
    func insert(_ alert: CoachAlert, into alerts: [CoachAlert]) async -> [CoachAlert] {
        var updated = alerts.filter { $0.type != alert.type && $0.isActive }
        updated.append(alert)
        return updated.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Tactical Advisor
/// Generates a single context-aware text string describing what the player should
/// do right now, based on game phase, economy, and objectives.
actor TacticalAdvisor {

    func advice(for state: LiveGameState) async -> String {
        switch state.sessionPhase {
        case .earlyGame:
            return earlyGameAdvice(state)
        case .midGame:
            return midGameAdvice(state)
        case .lateGame:
            return lateGameAdvice(state)
        case .loading:
            return "Game loading — review your draft strategy."
        case .draft:
            return "Draft in progress."
        default:
            return ""
        }
    }

    private func earlyGameAdvice(_ state: LiveGameState) -> String {
        let clock = state.gameTimeSeconds
        let lead = state.killScore.killLead

        if clock < 60 { return "Early game: farm your lane efficiently and avoid unnecessary trades." }
        if clock < 120 { return "Contest jungle buffs if your jungler needs support. Don't contest alone." }
        if clock < 180 { return "Turtle spawns at 3:00. Start grouping if you're near the pit." }
        if (180...300).contains(clock) {
            if lead > 0 { return "You're ahead — contest Turtle aggressively. Use your lead." }
            return "Turtle window: contest if safe, but don't throw your life away for it."
        }
        if lead > 2 { return "Early kill lead — pressure lanes and rotate for tower damage." }
        if lead < -2 { return "Behind in kills — farm safely, avoid risky fights, and defend towers." }
        return "Early game: farm efficiently and look for picks with your jungler."
    }

    private func midGameAdvice(_ state: LiveGameState) -> String {
        let clock = state.gameTimeSeconds
        let lead = state.killScore.killLead
        let turtleStatus = state.objectives.turtle.status

        if turtleStatus == .alive {
            return "Turtle is up — group all 5 and contest immediately."
        }
        if let secs = state.objectives.turtle.secondsUntilSpawn, secs <= 40 {
            return "Turtle respawning in \(secs)s — prepare to group."
        }
        if lead > 3 { return "Significant kill lead — group and push the exposed lane towers." }
        if lead < -3 { return "Behind — focus on farming and Turtle respawn. Avoid solo risks." }
        return "Mid game: group up after Turtle fights. Keep ward coverage on key bushes."
    }

    private func lateGameAdvice(_ state: LiveGameState) -> String {
        let lordStatus = state.objectives.lord.status
        let lead = state.killScore.killLead
        let clock = state.gameTimeSeconds

        if lordStatus == .alive {
            return "LORD is alive — this can win you the game. Group ALL 5 immediately."
        }
        if let secs = state.objectives.lord.secondsUntilSpawn, secs <= 30 {
            return "Lord spawning in \(secs)s — be at the pit with your full team."
        }
        if lead > 5 { return "Dominant lead — take Lord and end the game. Push inhibitors." }
        if lead < -5 { return "Severely behind — play for Lord steals and base defence. One lucky fight can reset the game." }
        return "Late game: all 5 group for Lord control and base siege. Never split in late game."
    }
}
