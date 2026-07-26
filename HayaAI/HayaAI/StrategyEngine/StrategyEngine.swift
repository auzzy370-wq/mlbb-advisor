import Foundation

// MARK: - Strategy Engine
actor StrategyEngine: StrategyEngineProtocol {

    func generateStrategy(
        friendlyHeroes: [Hero],
        enemyHeroes: [Hero],
        draftState: DraftState
    ) async throws -> DraftStrategy {
        var strategy = DraftStrategy()

        strategy.earlyGamePlan = generateEarlyPlan(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.midGamePlan = generateMidPlan(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.lateGamePlan = generateLatePlan(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.targetPriority = generateTargetPriority(enemies: enemyHeroes)
        strategy.objectivePriority = generateObjectivePriority(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.turtleTiming = computeTurtleTiming(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.lordTiming = computeLordTiming(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.splitPushAdvice = generateSplitPushAdvice(friendly: friendlyHeroes)
        strategy.teamfightAdvice = generateTeamfightAdvice(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.laneAssignments = generateLaneAssignments(heroes: friendlyHeroes)
        strategy.winConditions = generateWinConditions(friendly: friendlyHeroes, enemy: enemyHeroes)
        strategy.loseConditions = generateLoseConditions(friendly: friendlyHeroes, enemy: enemyHeroes)

        return strategy
    }

    // MARK: - Game Plans

    private func generateEarlyPlan(friendly: [Hero], enemy: [Hero]) -> String {
        let avgEarly = friendly.map { $0.earlyStrength }.average
        let enemyEarly = enemy.map { $0.earlyStrength }.average

        if avgEarly > enemyEarly + 1 {
            return "You have early game advantage. Invade enemy jungle, rotate for kills, and secure Turtle early. Apply pressure on all three lanes to snowball your lead."
        } else if enemyEarly > avgEarly + 1 {
            return "Play defensive early game. Avoid early fights and let your scaling heroes farm safely. Ward enemy jungle and react to ganks. Focus on denying their early objectives."
        } else {
            return "Even early game matchup. Contest Turtle at 4 minutes with vision control. Farm efficiently and look for skirmishes when you have numbers advantage."
        }
    }

    private func generateMidPlan(friendly: [Hero], enemy: [Hero]) -> String {
        let hasDive = friendly.contains { $0.mobility > 7 && $0.burst > 7 }
        let hasPoke = friendly.contains { $0.primaryRole == .mage && $0.burst > 6 }

        if hasDive {
            return "Use your dive composition to pick off isolated enemies. Rotate with your jungler and initiate 2v1 scenarios. Punish overextended enemies and force teamfights near objectives."
        } else if hasPoke {
            return "Poke enemies down before committing to fights. Use your mage's range advantage to zone enemies from objectives. Force bad trades and then capitalize when enemies are low."
        } else {
            return "Group mid and push as a unit. Secure vision around Turtle and Lord. Look for teamfights when you have ultimate advantages and punish enemies who are separated."
        }
    }

    private func generateLatePlan(friendly: [Hero], enemy: [Hero]) -> String {
        let avgLate = friendly.map { $0.lateStrength }.average
        let enemyLate = enemy.map { $0.lateStrength }.average

        if avgLate > enemyLate + 1 {
            return "You win in a prolonged game. Stall for time if needed, but push for Lord control. Your scaling heroes will outperform theirs in extended teamfights. Win through sustained combat."
        } else {
            return "Close the game before enemies outscale you. Prioritize Lord as soon as it spawns. Be decisive with objective control and avoid protracted sieges. End through base races if needed."
        }
    }

    // MARK: - Target Priority

    private func generateTargetPriority(enemies: [Hero]) -> [TargetPriority] {
        enemies
            .sorted { $0.sustain < $1.sustain }
            .enumerated()
            .map { index, hero in
                TargetPriority(
                    id: UUID().uuidString,
                    heroID: hero.id,
                    heroName: hero.name,
                    priority: index == 0 ? .critical : index == 1 ? .high : .medium,
                    reason: priorityReason(for: hero)
                )
            }
    }

    private func priorityReason(for hero: Hero) -> String {
        if hero.primaryRole == .marksman { return "High damage carry – eliminate first" }
        if hero.primaryRole == .mage { return "Magic damage dealer – focus before they burst your team" }
        if hero.primaryRole == .support { return "Support hero – silence their healing/CC" }
        if hero.primaryRole == .assassin { return "Assassin – dangerous when fed, burst early" }
        return "Key threat based on current build"
    }

    // MARK: - Objective Priority

    private func generateObjectivePriority(friendly: [Hero], enemy: [Hero]) -> [ObjectivePriority] {
        var objectives: [ObjectivePriority] = []

        let earlyScore = friendly.map { $0.earlyStrength }.average
        objectives.append(ObjectivePriority(
            id: UUID().uuidString,
            objective: .turtle,
            timing: earlyScore > 7 ? "4:00 – 5:00" : "5:00 – 6:00",
            reason: "First Turtle grants critical gold advantage",
            priority: earlyScore > 7 ? .critical : .high
        ))

        objectives.append(ObjectivePriority(
            id: UUID().uuidString,
            objective: .lord,
            timing: "After 18:00",
            reason: "Lord siege push can end the game",
            priority: .critical
        ))

        objectives.append(ObjectivePriority(
            id: UUID().uuidString,
            objective: .tower,
            timing: "After first pick-off",
            reason: "Tower denial reduces enemy income",
            priority: .high
        ))

        return objectives
    }

    // MARK: - Timings

    private func computeTurtleTiming(friendly: [Hero], enemy: [Hero]) -> String {
        let canFightEarly = friendly.map { $0.earlyStrength }.average > 6.5
        return canFightEarly
            ? "Contest first Turtle at 4:00. Set wards at 3:30. All 5 players should group."
            : "Secure vision at 4:30 but don't fight for Turtle if behind. Secure when safe."
    }

    private func computeLordTiming(friendly: [Hero], enemy: [Hero]) -> String {
        let isScaling = friendly.map { $0.scaling }.average > 7.5
        return isScaling
            ? "Farm through mid game and contest every Lord from 18:00 onwards. Your late game is stronger."
            : "Contest Lord aggressively starting 18:00. Use Lord siege to end before they outscale you."
    }

    // MARK: - Advice

    private func generateSplitPushAdvice(friendly: [Hero]) -> String {
        let splitPushers = friendly.filter { $0.mobility > 7 && $0.waveClear > 6 }
        if splitPushers.isEmpty {
            return "Your team isn't suited for split push. Group and push as 5."
        }
        let names = splitPushers.map { $0.name }.joined(separator: " or ")
        return "\(names) can split push effectively. Draw enemies then collapse for 4v3 teamfights."
    }

    private func generateTeamfightAdvice(friendly: [Hero], enemy: [Hero]) -> String {
        let ccScore = friendly.map { $0.crowdControl }.average
        let burstScore = friendly.map { $0.burst }.average

        if ccScore > 7 && burstScore > 7 {
            return "You have a strong teamfight composition. Initiate with your tank/engage and chain CC into your burst damage. Focus the backline first."
        } else if ccScore > 7 {
            return "Use your crowd control to lock down priority targets. Your team needs to follow up immediately on CC chains."
        } else if burstScore > 7 {
            return "All-in burst combo can one-shot carries. Coordinate ultimates for maximum burst windows."
        } else {
            return "Avoid messy teamfights. Use vision and pick off isolated enemies to generate advantages."
        }
    }

    // MARK: - Lane Assignments

    private func generateLaneAssignments(heroes: [Hero]) -> [LaneAssignment] {
        heroes.enumerated().map { index, hero in
            LaneAssignment(
                id: UUID().uuidString,
                heroID: hero.id,
                heroName: hero.name,
                assignedLane: hero.primaryLane,
                confidence: 0.85,
                reason: "Best lane for \(hero.name) based on role and kit"
            )
        }
    }

    // MARK: - Conditions

    private func generateWinConditions(friendly: [Hero], enemy: [Hero]) -> [String] {
        var conditions: [String] = []
        let earlyScore = friendly.map { $0.earlyStrength }.average
        if earlyScore > 7 { conditions.append("Snowball early kills into gold and objective leads") }
        let ccScore = friendly.map { $0.crowdControl }.average
        if ccScore > 7 { conditions.append("Win teamfights with superior crowd control chains") }
        let lateScore = friendly.map { $0.lateStrength }.average
        if lateScore > 7.5 { conditions.append("Scale to late game and outclass in extended fights") }
        conditions.append("Secure Lord buff and use siege to end the game")
        return conditions
    }

    private func generateLoseConditions(friendly: [Hero], enemy: [Hero]) -> [String] {
        var conditions: [String] = []
        let earlyScore = enemy.map { $0.earlyStrength }.average
        if earlyScore > 7 { conditions.append("Falling behind early to aggressive enemy") }
        let lateScore = enemy.map { $0.lateStrength }.average
        if lateScore > friendly.map({ $0.lateStrength }).average {
            conditions.append("Allowing the game to go too long – enemy outscales")
        }
        conditions.append("Losing multiple teamfights in a row before objectives")
        return conditions
    }
}

// MARK: - Double Array Average Helper
private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 5.0 }
        return reduce(0, +) / Double(count)
    }
}
