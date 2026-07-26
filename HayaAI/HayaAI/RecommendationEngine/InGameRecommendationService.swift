import Foundation

// MARK: - In-Game Recommendation Service
/// Consumes the DraftState (hero picks/bans from the draft) and LiveGameState
/// (current kill score, clock, objectives) and produces a full
/// InGameRecommendationPackage every time game state changes meaningfully.
actor InGameRecommendationService {

    private let heroDatabase: HeroDatabaseService
    private let itemEngine: ItemRecommendationEngine

    // State snapshots used for change detection
    private var lastPackagePhase: GameSessionPhase = .idle
    private var lastPackageClock: Int = -1
    private var lastKillLead: Int = 0

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.itemEngine = ItemRecommendationEngine()
    }

    // MARK: - Main Entry Point

    func generatePackage(
        playerHeroName: String,
        draftState: DraftState,
        gameState: LiveGameState
    ) async -> InGameRecommendationPackage? {

        guard !playerHeroName.isEmpty else { return nil }

        // Only regenerate when something meaningful changed
        let phaseChanged = gameState.sessionPhase != lastPackagePhase
        let clockBucket = gameState.gameTimeSeconds / 60      // regenerate every minute
        let clockChanged = clockBucket != lastPackageClock / 60
        let leadChanged = abs(gameState.killScore.killLead - lastKillLead) >= 2

        guard phaseChanged || clockChanged || leadChanged else { return nil }

        lastPackagePhase = gameState.sessionPhase
        lastPackageClock = gameState.gameTimeSeconds
        lastKillLead = gameState.killScore.killLead

        guard let playerHero = await heroDatabase.hero(byNameFuzzy: playerHeroName) else { return nil }

        let enemyHeroes = await resolveHeroes(from: draftState.enemyPicks.compactMap { $0.heroName })
        let allyHeroes = await resolveHeroes(from: draftState.friendlyPicks.compactMap { $0.heroName })

        let build = await buildProgression(for: playerHero, enemies: enemyHeroes, gameState: gameState)
        let targets = targetPriority(for: playerHero, enemies: enemyHeroes)
        let rotation = rotationAdvice(for: playerHero, gameState: gameState)
        let skillTips = skillTips(for: playerHero, gameState: gameState, enemies: enemyHeroes)
        let matchups = matchupTips(for: playerHero, enemies: enemyHeroes)
        let combo = comboReminder(for: playerHero, gameState: gameState)
        let powerNote = powerSpikeNote(for: playerHero, gameState: gameState)
        let oneLiner = oneLineAdvice(
            hero: playerHero,
            gameState: gameState,
            rotation: rotation
        )

        return InGameRecommendationPackage(
            heroName: playerHero.name,
            sessionPhase: gameState.sessionPhase,
            buildProgression: build,
            targetPriority: targets,
            currentRotation: rotation,
            skillTips: skillTips,
            matchupTips: matchups,
            comboReminder: combo,
            powerSpikeNote: powerNote,
            oneLineAdvice: oneLiner,
            generatedAt: Date()
        )
    }

    // MARK: - Build Progression

    private func buildProgression(
        for hero: Hero,
        enemies: [Hero],
        gameState: LiveGameState
    ) async -> BuildProgression {

        var steps: [BuildStep] = []
        let suggestedBuild = (try? await itemEngine.recommendBuild(
            for: hero,
            against: enemies,
            situation: buildSituation(gameState: gameState)
        )) ?? SuggestedBuild(coreItems: hero.preferredItems)

        let allItems = suggestedBuild.coreItems + suggestedBuild.situationalItems
        let ownedCount = estimateOwnedItems(gameState: gameState, totalItems: allItems.count)

        for (index, item) in allItems.enumerated() {
            let isOwned = index < ownedCount
            let isNext = index == ownedCount
            let urgency: BuildStep.BuildUrgency
            if suggestedBuild.counterItems.contains(where: { $0.id == item.id }) {
                urgency = .counter
            } else if suggestedBuild.situationalItems.contains(where: { $0.id == item.id }) {
                urgency = .situational
            } else {
                urgency = .core
            }

            let reason = itemReason(item: item, hero: hero, enemies: enemies, isNext: isNext, gameState: gameState)

            steps.append(BuildStep(
                id: "\(hero.id)-step-\(index)",
                order: index + 1,
                item: item,
                reason: reason,
                isNextToBuy: isNext,
                isAlreadyOwned: isOwned,
                costGold: estimatedCost(item: item),
                urgency: urgency
            ))
        }

        let goldNeeded = steps.first { !$0.isAlreadyOwned }.map { $0.costGold } ?? 0
        let completion = allItems.isEmpty ? 0.0 : Double(ownedCount) / Double(allItems.count)

        return BuildProgression(
            heroName: hero.name,
            steps: steps,
            currentGold: gameState.economy.friendlyGold,
            goldNeededForNext: max(0, goldNeeded - gameState.economy.friendlyGold),
            completionPercent: completion,
            buildNote: buildNote(hero: hero, gameState: gameState, enemies: enemies),
            lastUpdatedAt: Date()
        )
    }

    private func buildSituation(gameState: LiveGameState) -> BuildSituation {
        let lead = gameState.killScore.killLead
        let clock = gameState.gameTimeSeconds
        if lead >= 5 { return .snowball }
        if lead <= -5 { return .comeback }
        if clock > 900 { return .lateGame }
        return .standard
    }

    private func estimateOwnedItems(gameState: LiveGameState, totalItems: Int) -> Int {
        // Estimate from game time and gold: roughly 1 item per 180s + gold weighting
        let byTime = min(gameState.gameTimeSeconds / 180, totalItems)
        return byTime
    }

    private func estimatedCost(item: Item) -> Int {
        // Rough cost tiers by category
        switch item.category {
        case .movement: return 950
        case .physical, .magic: return 2300
        case .defense: return 2150
        case .jungling: return 1600
        case .roaming: return 800
        }
    }

    private func itemReason(item: Item, hero: Hero, enemies: [Hero], isNext: Bool, gameState: LiveGameState) -> String {
        if item.name.lowercased().contains("boots") { return "Movement speed and lane presence." }

        let hasHighSustain = enemies.contains { $0.sustain > 7 }
        let hasMagicDMG = enemies.contains { $0.damageType == .magic }
        let hasPhysicalDMG = enemies.contains { $0.damageType == .physical }

        if item.name.contains("Durance") || item.name.contains("Halberd") {
            return "Anti-heal — counters \(enemies.first { $0.sustain > 7 }?.name ?? "enemy sustain")."
        }
        if item.name.contains("Athena") || item.name.contains("Radiant") {
            return "Magic defense against \(enemies.first { $0.damageType == .magic }?.name ?? "enemy mage")."
        }
        if item.name.contains("Immortality") {
            return "Second life — essential in this stage of the game."
        }
        if item.category == .physical && hero.damageType == .physical {
            return "Core damage item for \(hero.primaryRole.rawValue) playstyle."
        }
        if item.category == .magic && hero.damageType == .magic {
            return "Core magic damage for your kit."
        }
        if item.category == .defense {
            if gameState.killScore.isBehind { return "Survivability — you need this while catching up." }
            return "Defense to survive focused attacks in teamfights."
        }
        return "Part of your optimal \(hero.name) build."
    }

    private func buildNote(hero: Hero, gameState: LiveGameState, enemies: [Hero]) -> String {
        let lead = gameState.killScore.killLead
        let hasSustain = enemies.contains { $0.sustain > 7 }

        var notes: [String] = []
        if hasSustain { notes.append("Buy anti-heal early — enemy has high sustain.") }
        if lead >= 4 { notes.append("Ahead: prioritise damage to close out fast.") }
        if lead <= -4 { notes.append("Behind: grab defensive items sooner than usual.") }
        if notes.isEmpty { notes.append("Follow the core build order for \(hero.name).") }
        return notes.joined(separator: " ")
    }

    // MARK: - Target Priority

    private func targetPriority(for hero: Hero, enemies: [Hero]) -> [TargetRecommendation] {
        guard !enemies.isEmpty else { return [] }

        return enemies
            .sorted { priorityScore($0, attacker: hero) > priorityScore($1, attacker: hero) }
            .enumerated()
            .map { index, enemy in
                TargetRecommendation(
                    id: "\(hero.id)-target-\(enemy.id)",
                    heroName: enemy.name,
                    heroRole: enemy.primaryRole,
                    priority: TargetPriority(raw: index + 1),
                    reason: targetReason(attacker: hero, target: enemy),
                    howToKill: howToKill(attacker: hero, target: enemy),
                    dangerLevel: dangerLevel(attacker: hero, threat: enemy),
                    canYouKill: canKill(attacker: hero, target: enemy)
                )
            }
    }

    private func priorityScore(_ enemy: Hero, attacker: Hero) -> Double {
        var score = 0.0
        // Squishies first
        score += (10 - enemy.sustain) * 1.2
        // Heroes that counter attacker are higher priority (kill them before they kill you)
        if enemy.counterHeroes.contains(attacker.name) { score += 3 }
        // Carries (marksman, mage) are priority targets
        if enemy.primaryRole == .marksman { score += 4 }
        if enemy.primaryRole == .mage { score += 3 }
        if enemy.primaryRole == .assassin { score += 2 }
        // Late-game threats
        score += enemy.lateStrength * 0.5
        return score
    }

    private func targetReason(attacker: Hero, target: Hero) -> String {
        if target.primaryRole == .marksman {
            return "Main damage carry — removing them cripples enemy DPS."
        }
        if target.primaryRole == .mage {
            return "Magic burst damage — silence them to protect your team."
        }
        if target.primaryRole == .support || target.primaryRole == .roamer {
            return "Eliminating their healer/CC disrupts enemy coordination."
        }
        if target.primaryRole == .assassin {
            return "Dangerous if fed — kill before they reach your carries."
        }
        if target.primaryRole == .tank {
            return "Tank is last priority unless they have critical CC for your team."
        }
        return "High-value target based on your hero's kit."
    }

    private func howToKill(attacker: Hero, target: Hero) -> String {
        if attacker.burst > 8 {
            return "Burst them with your full combo before they can react. Prioritise isolation."
        }
        if attacker.crowdControl > 8 {
            return "Land your CC first, then let teammates follow up. Don't fight alone."
        }
        if attacker.mobility > 8 {
            return "Use your mobility to dive past the frontline and hit them directly."
        }
        return "Wait for an opening when they've used key skills, then commit."
    }

    private func dangerLevel(attacker: Hero, threat: Hero) -> TargetRecommendation.DangerLevel {
        if threat.counteredBy.contains(attacker.name) { return .safe }
        if threat.counterHeroes.contains(attacker.name) { return .extreme }
        if threat.burst > 8 || threat.crowdControl > 8 { return .dangerous }
        if threat.primaryRole == .assassin { return .dangerous }
        return .moderate
    }

    private func canKill(attacker: Hero, target: Hero) -> Bool {
        !attacker.counteredBy.contains(target.name) && attacker.burst >= target.sustain - 1
    }

    // MARK: - Rotation Advice

    private func rotationAdvice(for hero: Hero, gameState: LiveGameState) -> RotationAdvice {
        let clock = gameState.gameTimeSeconds
        let lead = gameState.killScore.killLead
        let turtle = gameState.objectives.turtle
        let lord = gameState.objectives.lord

        // Lord alive = always go there
        if lord.status == .alive {
            return RotationAdvice(
                destination: .lord,
                urgency: .immediate,
                reason: "Lord is alive. This is the highest priority objective in the game.",
                timeWindow: "Go immediately — don't delay",
                afterRotation: "Fight for Lord. If you secure it, push with the siege buff.",
                alternativeIfBehind: "Even if behind, contest Lord — one good fight can reset the game."
            )
        }

        // Lord spawning soon
        if let secs = lord.secondsUntilSpawn, secs <= 45 {
            return RotationAdvice(
                destination: .lord,
                urgency: .immediate,
                reason: "Lord spawns in \(secs)s. Your whole team must be there.",
                timeWindow: "Start rotating right now",
                afterRotation: "Set vision and wait for spawn. Fight when it appears.",
                alternativeIfBehind: "Steal attempt with Retribution if behind."
            )
        }

        // Turtle alive in early/mid game
        if turtle.status == .alive && clock < 900 {
            return RotationAdvice(
                destination: .turtle,
                urgency: .immediate,
                reason: "Turtle is alive. Contest for the gold and XP bonus.",
                timeWindow: "Go now before enemies take it free",
                afterRotation: "After Turtle, push the nearest exposed tower.",
                alternativeIfBehind: "Only contest if you can win the fight. Don't die for it."
            )
        }

        // Turtle spawning soon in early game
        if let secs = turtle.secondsUntilSpawn, secs <= 40, clock < 900 {
            return RotationAdvice(
                destination: .turtle,
                urgency: .soon,
                reason: "Turtle spawns in \(secs)s. Wrap up your lane and rotate.",
                timeWindow: "In the next \(secs) seconds",
                afterRotation: "Take Turtle then push mid or EXP lane tower.",
                alternativeIfBehind: "Farm safely if you can't win the fight."
            )
        }

        // Role-based rotation logic
        switch hero.primaryLane {
        case .jungle:
            if lead > 0 {
                return RotationAdvice(
                    destination: .enemyJungle,
                    urgency: .soon,
                    reason: "You're ahead — invade the enemy jungle to deny their jungler.",
                    timeWindow: "When your buffs are cleared",
                    afterRotation: "Steal their buff or force a fight 2v1.",
                    alternativeIfBehind: "Farm your own jungle safely and wait for a pick opportunity."
                )
            }
            return RotationAdvice(
                destination: .midLane,
                urgency: .whenReady,
                reason: "Gank mid lane to create pressure and help your mage roam.",
                timeWindow: "After clearing your jungle route",
                afterRotation: "Take mid outer tower if the gank succeeds.",
                alternativeIfBehind: "Farm red/blue buff and look for counter-gank opportunities."
            )

        case .roam:
            return RotationAdvice(
                destination: .goldLane,
                urgency: .soon,
                reason: "Your gold laner needs support. Set up a gank or zone the enemy.",
                timeWindow: "After helping mid with vision",
                afterRotation: "Rotate to Turtle after securing gold lane priority.",
                alternativeIfBehind: "Stay with your most fed ally to protect them."
            )

        case .mid:
            if clock < 300 {
                return RotationAdvice(
                    destination: .expLane,
                    urgency: .whenReady,
                    reason: "Mid has priority — rotate top to help your EXP laner.",
                    timeWindow: "After pushing mid wave",
                    afterRotation: "Come back mid to contest the next wave.",
                    alternativeIfBehind: "Don't rotate — stay mid and outfarm."
                )
            }
            return RotationAdvice(
                destination: .turtle,
                urgency: .soon,
                reason: "Mid should lead the Turtle contest. Push wave then group.",
                timeWindow: "After shoving your wave",
                afterRotation: "Siege mid tower with Turtle buff.",
                alternativeIfBehind: "Farm mid and wait for a mistake to engage."
            )

        default:
            return RotationAdvice(
                destination: .midLane,
                urgency: .whenReady,
                reason: "Group mid after winning your lane for a 5v5 push.",
                timeWindow: "When all 5 are healthy",
                afterRotation: "Siege mid tower then take Turtle or Lord.",
                alternativeIfBehind: "Play safe on your lane and farm to your power spike."
            )
        }
    }

    // MARK: - Skill Tips

    private func skillTips(for hero: Hero, gameState: LiveGameState, enemies: [Hero]) -> [SkillTip] {
        var tips: [SkillTip] = []
        let hasCC = hero.crowdControl > 7
        let hasBurst = hero.burst > 7
        let hasMobility = hero.mobility > 7
        let clock = gameState.gameTimeSeconds

        // S1 tip
        tips.append(SkillTip(
            id: "\(hero.id)-s1",
            skillName: "Skill 1",
            tip: hasCC
                ? "Lead with S1 to land CC before the enemy can react."
                : hasBurst
                    ? "Use S1 to open your burst combo or poke safely from range."
                    : "Use S1 for wave clear and trading safely.",
            useNow: gameState.sessionPhase == .earlyGame && clock < 300,
            cooldownNote: "Hold S1 if you're about to engage — don't waste it on minions.",
            comboHint: hero.combos.first.map { $0.skill }
        ))

        // S2 tip
        tips.append(SkillTip(
            id: "\(hero.id)-s2",
            skillName: "Skill 2",
            tip: hasMobility
                ? "S2 is your escape/engage tool. Save it until you know which way the fight goes."
                : "S2 is your main damage. Combo it with basic attacks for maximum output.",
            useNow: false,
            cooldownNote: hasMobility ? "Never use S2 aggressively unless you have S3 ready." : nil,
            comboHint: nil
        ))

        // Ult tip
        let ultTip = ultTip(hero: hero, gameState: gameState, enemies: enemies)
        tips.append(ultTip)

        // Passive tip
        if !hero.combos.isEmpty {
            tips.append(SkillTip(
                id: "\(hero.id)-passive",
                skillName: "Combo",
                tip: hero.combos.first?.note ?? "Follow your optimal combo order.",
                useNow: gameState.killScore.isAhead,
                cooldownNote: nil,
                comboHint: hero.combos.first?.skill
            ))
        }

        return tips
    }

    private func ultTip(hero: Hero, gameState: LiveGameState, enemies: [Hero]) -> SkillTip {
        let objectiveUp = gameState.objectives.turtle.status == .alive ||
                          gameState.objectives.lord.status == .alive
        let inFight = gameState.minimap.detectedEnemyPositions.count >= 3

        let tip: String
        let useNow: Bool
        let cooldownNote: String

        if objectiveUp {
            tip = "An objective is up — save your ultimate for the objective fight, not random skirmishes."
            useNow = false
            cooldownNote = "Don't waste ult before the objective fight starts."
        } else if inFight {
            tip = "Enemies grouped — your ult has maximum value right now in a teamfight."
            useNow = true
            cooldownNote = "Use when 3+ enemies are in range for the most impact."
        } else if hero.burst > 8 {
            tip = "Save your ult for isolated squishy targets. Don't waste it on tanks."
            useNow = false
            cooldownNote = "Only use ult when you can guarantee a kill."
        } else if hero.crowdControl > 8 {
            tip = "Your ult is for initiating or peeling. Use it to save a teammate or to engage."
            useNow = false
            cooldownNote = "Don't use ult when already winning the fight — save for the next engage."
        } else {
            tip = "Use your ultimate at the peak of the fight when enemies are grouped or low."
            useNow = inFight
            cooldownNote = "Coordinate ult timing with your tank's initiation."
        }

        return SkillTip(
            id: "\(hero.id)-ult",
            skillName: "Ultimate",
            tip: tip,
            useNow: useNow,
            cooldownNote: cooldownNote,
            comboHint: hero.combos.last?.skill
        )
    }

    // MARK: - Matchup Tips

    private func matchupTips(for hero: Hero, enemies: [Hero]) -> [MatchupTip] {
        enemies.map { enemy in
            MatchupTip(
                id: "\(hero.id)-vs-\(enemy.id)",
                enemyHeroName: enemy.name,
                tip: matchupTipText(attacker: hero, target: enemy),
                avoidNote: avoidNote(attacker: hero, target: enemy),
                counterSkill: counterSkill(attacker: hero, target: enemy),
                windowToFight: fightWindow(target: enemy)
            )
        }
    }

    private func matchupTipText(attacker: Hero, target: Hero) -> String {
        if attacker.counterHeroes.contains(target.name) {
            return "You have a natural advantage against \(target.name). Play aggressive and look for trades."
        }
        if attacker.counteredBy.contains(target.name) {
            return "\(target.name) counters you. Play safe, avoid extended fights, and look for pick-offs."
        }
        if target.mobility > 8 {
            return "\(target.name) is very mobile. Wait for them to use their dash before committing."
        }
        if target.burst > 8 {
            return "\(target.name) can burst you. Stay at a safe distance and don't fight them alone."
        }
        if target.crowdControl > 8 {
            return "\(target.name) has strong CC. Use your mobility to avoid being locked down."
        }
        return "Neutral matchup against \(target.name). Trade carefully and look for their mistakes."
    }

    private func avoidNote(attacker: Hero, target: Hero) -> String {
        if target.crowdControl > 8 { return "Don't walk into their CC range without a clear escape." }
        if target.burst > 8 { return "Never fight 1v1 when their burst skills are off cooldown." }
        if target.sustain > 8 { return "Don't engage in extended trades — they out-sustain you." }
        return "Don't overextend when they have ult available."
    }

    private func counterSkill(attacker: Hero, target: Hero) -> String? {
        if attacker.crowdControl > 7 { return "S1 (CC) — land this to stop their dash/escape" }
        if attacker.mobility > 8 { return "S2 (dash) — dodge their key skill then burst" }
        return nil
    }

    private func fightWindow(target: Hero) -> String {
        if target.burst > 8 { return "Fight after they waste their burst skills on minions or another target." }
        if target.mobility > 8 { return "Fight when their dash skill is on cooldown (watch for the animation)." }
        if target.crowdControl > 8 { return "Fight after they land CC on someone else — they can't CC twice quickly." }
        return "Fight when they're isolated away from their team."
    }

    // MARK: - Combo Reminder

    private func comboReminder(for hero: Hero, gameState: LiveGameState) -> ComboReminder? {
        guard let combo = hero.combos.first else { return nil }
        let steps = combo.skill.components(separatedBy: CharacterSet(charactersIn: "→ "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ComboReminder(
            id: "\(hero.id)-combo-reminder",
            name: "Core Combo",
            steps: steps,
            context: combo.note ?? "Use in 1v1 or gank situations",
            triggerCondition: gameState.killScore.isAhead
                ? "Enemy is alone — go in with full combo"
                : "Wait for jungler backup before using full combo"
        )
    }

    // MARK: - Power Spike Note

    private func powerSpikeNote(for hero: Hero, gameState: LiveGameState) -> String {
        let clock = gameState.gameTimeSeconds
        for spike in hero.powerSpikes {
            switch spike.phase {
            case .early where clock < 480:
                return "You should be at your \(spike.phase.rawValue.lowercased()) power spike now. \(spike.description)"
            case .mid where (480...900).contains(clock):
                return "Mid-game power spike: \(spike.description)"
            case .late where clock > 900:
                return "Late-game power spike active: \(spike.description)"
            default:
                continue
            }
        }
        if clock < 300 { return "Farm efficiently to reach your first item power spike." }
        return "Focus on building your core items to unlock your full potential."
    }

    // MARK: - One-Line Advice

    private func oneLineAdvice(hero: Hero, gameState: LiveGameState, rotation: RotationAdvice) -> String {
        let lead = gameState.killScore.killLead
        let lord = gameState.objectives.lord
        let turtle = gameState.objectives.turtle
        let clock = gameState.gameTimeSeconds

        if lord.status == .alive { return "LORD IS UP — group all 5 and fight for it now." }
        if turtle.status == .alive && clock < 900 { return "Turtle is alive — rotate and contest it." }
        if let secs = lord.secondsUntilSpawn, secs <= 30 { return "Lord in \(secs)s — everyone to the Lord pit." }
        if let secs = turtle.secondsUntilSpawn, secs <= 20, clock < 900 { return "Turtle in \(secs)s — start grouping." }

        if gameState.playerState.currentHP < 0.2 { return "LOW HP — retreat to base immediately." }
        if gameState.playerState.currentHP < 0.35 { return "Back off — you're too low to fight." }

        if lead >= 5 { return "Big lead — push with your team and take towers." }
        if lead <= -5 { return "You're behind — farm and play for Lord reset." }

        return "\(rotation.urgency.rawValue): \(rotation.destination.rawValue)"
    }

    // MARK: - Helpers

    private func resolveHeroes(from names: [String]) async -> [Hero] {
        var result: [Hero] = []
        for name in names where !name.isEmpty {
            if let h = await heroDatabase.hero(byNameFuzzy: name) { result.append(h) }
        }
        return result
    }
}

// MARK: - TargetPriority helper initialiser
extension TargetPriority {
    init(raw: Int) {
        self.init(
            id: UUID().uuidString,
            heroID: "",
            heroName: "",
            priority: raw == 1 ? .critical : raw == 2 ? .high : .medium,
            reason: ""
        )
    }
}
