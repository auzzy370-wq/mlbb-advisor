import Foundation

// MARK: - Recommendation Engine
/// Scores every available hero across 8 dimensions and returns the top N recommendations.
actor RecommendationEngine: RecommendationEngineProtocol {

    // MARK: - Dependencies
    private let heroDatabase: HeroDatabaseService
    private let teamAnalyzer: TeamCompositionAnalyzer
    private let comfortTracker: ComfortTracker

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.teamAnalyzer = TeamCompositionAnalyzer()
        self.comfortTracker = ComfortTracker()
    }

    // MARK: - Main API

    func generateRecommendations(
        for draftState: DraftState,
        userProfile: UserProfile?,
        limit: Int = 5
    ) async throws -> RecommendationResult {

        let allHeroes = await heroDatabase.heroes
        let unavailableIDs = Set(draftState.unavailableHeroIDs)
        let availableHeroes = allHeroes.filter { !unavailableIDs.contains($0.id) && !unavailableIDs.contains($0.name) }

        guard !availableHeroes.isEmpty else {
            return RecommendationResult(recommendations: [], draftState: draftState, teamAnalysis: TeamCompositionAnalysis())
        }

        // Resolve hero objects from IDs
        let friendlyHeroes = await resolveHeroes(ids: draftState.friendlyHeroIDs, names: draftState.friendlyPicks.compactMap { $0.heroName })
        let enemyHeroes = await resolveHeroes(ids: draftState.enemyHeroIDs, names: draftState.enemyPicks.compactMap { $0.heroName })

        // Analyse current friendly composition
        let teamAnalysis = await teamAnalyzer.analyze(heroes: friendlyHeroes)

        // Score all available heroes concurrently
        let scoredHeroes = await withTaskGroup(of: HeroRecommendation?.self) { group in
            for hero in availableHeroes {
                group.addTask {
                    var scores = await self.computeScores(
                        hero: hero,
                        friendlyHeroes: friendlyHeroes,
                        enemyHeroes: enemyHeroes,
                        teamAnalysis: teamAnalysis,
                        draftState: draftState,
                        userProfile: userProfile
                    )
                    scores.computeOverall()
                    var recommendation = HeroRecommendation(hero: hero, scores: scores)
                    recommendation = await self.enrichRecommendation(
                        recommendation,
                        friendlyHeroes: friendlyHeroes,
                        enemyHeroes: enemyHeroes,
                        draftState: draftState
                    )
                    return recommendation
                }
            }

            var results: [HeroRecommendation] = []
            for await rec in group {
                if let rec { results.append(rec) }
            }
            return results
        }

        let sorted = scoredHeroes
            .sorted { $0.scores.overallScore > $1.scores.overallScore }
            .prefix(limit)
            .enumerated()
            .map { index, rec -> HeroRecommendation in
                var r = rec
                r.rank = index + 1
                return r
            }

        return RecommendationResult(
            recommendations: Array(sorted),
            draftState: draftState,
            teamAnalysis: teamAnalysis
        )
    }

    func scoreHero(
        _ hero: Hero,
        draftState: DraftState,
        userProfile: UserProfile?
    ) async throws -> HeroScoreComponents {
        let friendlyHeroes = await resolveHeroes(ids: [], names: draftState.friendlyPicks.compactMap { $0.heroName })
        let enemyHeroes = await resolveHeroes(ids: [], names: draftState.enemyPicks.compactMap { $0.heroName })
        let teamAnalysis = await teamAnalyzer.analyze(heroes: friendlyHeroes)
        var scores = await computeScores(
            hero: hero,
            friendlyHeroes: friendlyHeroes,
            enemyHeroes: enemyHeroes,
            teamAnalysis: teamAnalysis,
            draftState: draftState,
            userProfile: userProfile
        )
        scores.computeOverall()
        return scores
    }

    func analyzeTeamComposition(heroIDs: [String], team: DraftTurn) async throws -> TeamCompositionAnalysis {
        let heroes = await heroDatabase.heroes.filter { heroIDs.contains($0.id) }
        return await teamAnalyzer.analyze(heroes: heroes)
    }

    // MARK: - Score Computation

    private func computeScores(
        hero: Hero,
        friendlyHeroes: [Hero],
        enemyHeroes: [Hero],
        teamAnalysis: TeamCompositionAnalysis,
        draftState: DraftState,
        userProfile: UserProfile?
    ) async -> HeroScoreComponents {
        var scores = HeroScoreComponents()

        scores.counterScore = computeCounterScore(hero: hero, enemies: enemyHeroes)
        scores.synergyScore = computeSynergyScore(hero: hero, allies: friendlyHeroes)
        scores.laneScore = computeLaneScore(hero: hero, teamAnalysis: teamAnalysis, draftState: draftState)
        scores.metaScore = hero.metaScore
        scores.scalingScore = hero.scaling
        scores.comfortScore = await computeComfortScore(hero: hero, userProfile: userProfile)
        scores.difficultyScore = computeDifficultyScore(hero: hero, userProfile: userProfile)
        scores.executionScore = computeExecutionScore(hero: hero, teamAnalysis: teamAnalysis)

        return scores
    }

    private func computeCounterScore(hero: Hero, enemies: [Hero]) -> Double {
        guard !enemies.isEmpty else { return 5.0 }

        var score = 5.0
        let enemyIDs = Set(enemies.map { $0.id })
        let enemyNames = Set(enemies.map { $0.name })

        // Bonus for heroes that counter enemies
        for enemyName in enemyNames where hero.counterHeroes.contains(enemyName) {
            score += 1.5
        }

        // Penalty for being countered by enemies
        for enemyName in enemyNames where hero.counteredBy.contains(enemyName) {
            score -= 1.5
        }

        // Strong/Weak against role checks
        for enemy in enemies {
            if hero.strongAgainst.contains(enemy.primaryRole.rawValue) ||
               hero.strongAgainst.contains(enemy.name) {
                score += 0.8
            }
            if hero.weakAgainst.contains(enemy.primaryRole.rawValue) ||
               hero.weakAgainst.contains(enemy.name) {
                score -= 0.8
            }
        }

        return min(10.0, max(0.0, score))
    }

    private func computeSynergyScore(hero: Hero, allies: [Hero]) -> Double {
        guard !allies.isEmpty else { return 5.0 }

        var score = 5.0
        let allyRoles = allies.flatMap { $0.roles }

        // Fill missing damage type
        let hasMagic = allies.contains { $0.damageType == .magic || $0.damageType == .hybrid }
        let hasPhysical = allies.contains { $0.damageType == .physical || $0.damageType == .hybrid }

        if hero.damageType == .magic && !hasMagic { score += 1.5 }
        if hero.damageType == .physical && !hasPhysical { score += 1.5 }

        // Check team needs
        let hasTank = allyRoles.contains(.tank)
        let hasSupport = allyRoles.contains(.support)
        let hasMarksman = allyRoles.contains(.marksman)
        let hasMage = allyRoles.contains(.mage)

        if !hasTank && (hero.primaryRole == .tank || hero.primaryRole == .fighter) { score += 1.5 }
        if !hasMarksman && hero.primaryRole == .marksman { score += 1.5 }
        if !hasMage && hero.primaryRole == .mage { score += 1.0 }
        if !hasSupport && (hero.primaryRole == .support || hero.primaryRole == .roamer) { score += 1.0 }

        // Crowd control bonus if team lacks it
        let allyCC = allies.map { $0.crowdControl }.reduce(0, +) / Double(allies.count)
        if allyCC < 5.0 && hero.crowdControl > 7.0 { score += 1.0 }

        return min(10.0, max(0.0, score))
    }

    private func computeLaneScore(hero: Hero, teamAnalysis: TeamCompositionAnalysis, draftState: DraftState) -> Double {
        var score = 5.0
        // Heroes with higher lane flexibility get a slight bonus
        if hero.secondaryLane != nil { score += 0.5 }
        // Prefer heroes that excel early if team has early weakness
        if teamAnalysis.earlyGameScore < 5.0 && hero.earlyStrength > 7.0 { score += 1.5 }
        // Prefer late-game heroes if team has late-game weakness
        if teamAnalysis.lateGameScore < 5.0 && hero.lateStrength > 7.0 { score += 1.0 }
        return min(10.0, max(0.0, score))
    }

    private func computeComfortScore(hero: Hero, userProfile: UserProfile?) async -> Double {
        guard let profile = userProfile else { return 5.0 }
        var score = 5.0
        if profile.favoriteHeroes.contains(hero.id) || profile.favoriteHeroes.contains(hero.name) {
            score += 3.0
        }
        if profile.preferredRoles.contains(hero.primaryRole) { score += 1.5 }
        if let wr = profile.heroWinRates[hero.id] ?? profile.heroWinRates[hero.name] {
            score += wr.winRate * 2.0
        }
        return min(10.0, max(0.0, score))
    }

    private func computeDifficultyScore(hero: Hero, userProfile: UserProfile?) -> Double {
        // Easier heroes score higher for difficulty component (penalise extreme difficulty)
        let baseScore = Double(5 - hero.difficulty.rawValue) * 2.0 + 2.0
        return min(10.0, max(0.0, baseScore))
    }

    private func computeExecutionScore(hero: Hero, teamAnalysis: TeamCompositionAnalysis) -> Double {
        var score = 5.0
        // Heroes with simple combos get execution bonus
        if hero.difficulty == .easy || hero.difficulty == .moderate { score += 2.0 }
        // Heroes that synergise with team comp
        if hero.crowdControl > 7 && teamAnalysis.crowdControlScore < 6 { score += 1.5 }
        return min(10.0, max(0.0, score))
    }

    // MARK: - Enrichment

    private func enrichRecommendation(
        _ recommendation: HeroRecommendation,
        friendlyHeroes: [Hero],
        enemyHeroes: [Hero],
        draftState: DraftState
    ) async -> HeroRecommendation {
        var rec = recommendation
        let hero = rec.hero

        // Build reasons
        rec.reason = buildReason(hero: hero, friendlyHeroes: friendlyHeroes, enemyHeroes: enemyHeroes, scores: rec.scores)
        rec.advantages = buildAdvantages(hero: hero, enemies: enemyHeroes)
        rec.weaknesses = buildWeaknesses(hero: hero, enemies: enemyHeroes)

        // Lane assignment
        rec.laneAssignment = hero.primaryLane

        // Build suggestion
        rec.suggestedBuild = SuggestedBuild(
            coreItems: hero.preferredItems,
            situationalItems: hero.situationalItems,
            counterItems: hero.counterItems,
            boots: hero.preferredItems.first { $0.name.lowercased().contains("boots") },
            buildExplanation: buildBuildExplanation(hero: hero, enemies: enemyHeroes)
        )

        rec.strategyNote = buildStrategyNote(hero: hero, draftState: draftState)
        return rec
    }

    private func buildReason(hero: Hero, friendlyHeroes: [Hero], enemyHeroes: [Hero], scores: HeroScoreComponents) -> String {
        var parts: [String] = []
        if scores.counterScore > 7.5 { parts.append("counters enemy lineup") }
        if scores.synergyScore > 7.5 { parts.append("synergises well with your team") }
        if scores.metaScore > 8 { parts.append("strong meta pick") }
        if scores.laneScore > 7.5 { parts.append("fills a team gap") }
        if scores.scalingScore > 8 { parts.append("scales into late game") }
        guard !parts.isEmpty else { return "Solid overall pick for this draft." }
        return "\(hero.name) \(parts.joined(separator: ", "))."
    }

    private func buildAdvantages(hero: Hero, enemies: [Hero]) -> [String] {
        var advantages: [String] = []
        let enemyNames = enemies.map { $0.name }
        let countered = hero.counterHeroes.filter { enemyNames.contains($0) }
        if !countered.isEmpty { advantages.append("Counters \(countered.joined(separator: ", "))") }
        if hero.mobility > 8 { advantages.append("High mobility for escape and chasing") }
        if hero.crowdControl > 8 { advantages.append("Strong crowd control") }
        if hero.burst > 8 { advantages.append("Excellent burst damage") }
        if hero.lateStrength > 8 { advantages.append("Dominant late game") }
        return advantages
    }

    private func buildWeaknesses(hero: Hero, enemies: [Hero]) -> [String] {
        var weaknesses: [String] = []
        let enemyNames = enemies.map { $0.name }
        let counters = hero.counteredBy.filter { enemyNames.contains($0) }
        if !counters.isEmpty { weaknesses.append("Countered by \(counters.joined(separator: ", "))") }
        if hero.difficulty == .extreme { weaknesses.append("High execution difficulty") }
        if hero.sustain < 3 { weaknesses.append("Low sustain – avoid extended trades") }
        if hero.earlyStrength < 5 { weaknesses.append("Weak early game – play safe") }
        return weaknesses
    }

    private func buildBuildExplanation(hero: Hero, enemies: [Hero]) -> String {
        let hasMagic = enemies.contains { $0.damageType == .magic }
        let hasPhysical = enemies.contains { $0.damageType == .physical }
        var note = "Core build focuses on \(hero.damageType.rawValue.lowercased()) damage. "
        if hasMagic { note += "Include magic defense against their mages. " }
        if hasPhysical { note += "Physical armor recommended against their fighters. " }
        return note
    }

    private func buildStrategyNote(hero: Hero, draftState: DraftState) -> String {
        switch draftState.phase {
        case .pickPhase1, .pickPhase2:
            return "\(hero.name) is \(hero.difficulty.label) difficulty. Best in \(hero.primaryLane.rawValue) lane. Focus on \(hero.earlyStrength > 7 ? "early aggression" : "scaling into mid/late game")."
        case .banPhase1, .banPhase2:
            return "\(hero.name) has \(String(format: "%.0f", hero.banPriority * 10))% ban priority this patch."
        default:
            return hero.rotationGuide
        }
    }

    // MARK: - Helpers

    private func resolveHeroes(ids: [String], names: [String]) async -> [Hero] {
        var result: [Hero] = []
        for id in ids {
            if let hero = await heroDatabase.hero(byID: id) { result.append(hero) }
        }
        for name in names where !name.isEmpty {
            if let hero = await heroDatabase.hero(byName: name) {
                if !result.contains(hero) { result.append(hero) }
            } else if let hero = await heroDatabase.hero(byNameFuzzy: name) {
                if !result.contains(hero) { result.append(hero) }
            }
        }
        return result
    }
}

// MARK: - Team Composition Analyzer
actor TeamCompositionAnalyzer {

    func analyze(heroes: [Hero]) async -> TeamCompositionAnalysis {
        guard !heroes.isEmpty else { return TeamCompositionAnalysis() }

        var analysis = TeamCompositionAnalysis()
        let count = Double(heroes.count)

        analysis.frontlineScore = heroes.filter { $0.primaryRole == .tank || $0.primaryRole == .fighter }.map { _ in 10.0 }.average ?? 0
        analysis.backlineScore = heroes.filter { $0.primaryRole == .marksman || $0.primaryRole == .mage }.map { _ in 10.0 }.average ?? 0
        analysis.magicDamageScore = heroes.filter { $0.damageType == .magic }.count > 0 ? 7.0 : 2.0
        analysis.physicalDamageScore = heroes.filter { $0.damageType == .physical }.count > 0 ? 7.0 : 2.0
        analysis.burstScore = heroes.map { $0.burst }.reduce(0, +) / count
        analysis.sustainScore = heroes.map { $0.sustain }.reduce(0, +) / count
        analysis.crowdControlScore = heroes.map { $0.crowdControl }.reduce(0, +) / count
        analysis.waveClearScore = heroes.map { $0.waveClear }.reduce(0, +) / count
        analysis.objectiveControlScore = heroes.map { $0.objectiveControl }.reduce(0, +) / count
        analysis.roamScore = heroes.filter { $0.primaryRole == .roamer || $0.primaryRole == .support }.map { _ in 10.0 }.average ?? 0
        analysis.scalingScore = heroes.map { $0.scaling }.reduce(0, +) / count
        analysis.earlyGameScore = heroes.map { $0.earlyStrength }.reduce(0, +) / count
        analysis.lateGameScore = heroes.map { $0.lateStrength }.reduce(0, +) / count
        analysis.splitPushScore = heroes.filter { $0.mobility > 7 }.map { $0.waveClear }.average ?? 0
        analysis.diveScore = heroes.filter { $0.mobility > 7 && $0.burst > 7 }.count > 0 ? 8.0 : 3.0
        analysis.pokeScore = heroes.filter { $0.primaryRole == .mage || $0.primaryRole == .marksman }.map { $0.burst }.average ?? 0
        analysis.siegeScore = heroes.map { $0.waveClear }.reduce(0, +) / count

        analysis.weaknesses = computeWeaknesses(analysis: analysis)
        analysis.suggestions = computeSuggestions(analysis: analysis, heroes: heroes)

        return analysis
    }

    private func computeWeaknesses(analysis: TeamCompositionAnalysis) -> [String] {
        var weaknesses: [String] = []
        if analysis.frontlineScore < 4 { weaknesses.append("Lacks frontline – vulnerable to poke") }
        if analysis.crowdControlScore < 4 { weaknesses.append("Insufficient crowd control") }
        if analysis.sustainScore < 3 { weaknesses.append("Low sustain – avoid extended engagements") }
        if analysis.waveClearScore < 4 { weaknesses.append("Weak wave clear – prone to tower pressure") }
        if analysis.lateGameScore < 5 { weaknesses.append("Weak late game – need early wins") }
        if analysis.magicDamageScore < 3 { weaknesses.append("No magic damage – enemy can build only physical defense") }
        if analysis.physicalDamageScore < 3 { weaknesses.append("No physical damage – enemy can build only magic defense") }
        return weaknesses
    }

    private func computeSuggestions(analysis: TeamCompositionAnalysis, heroes: [Hero]) -> [String] {
        var suggestions: [String] = []
        if analysis.frontlineScore < 4 { suggestions.append("Pick a Tank or Fighter for EXP or Roam") }
        if analysis.crowdControlScore < 4 { suggestions.append("Add a hero with crowd control (Franco, Khufra, Atlas)") }
        if analysis.sustainScore < 3 { suggestions.append("Consider a healer or sustain support") }
        if analysis.waveClearScore < 4 { suggestions.append("Add a hero with strong wave clear for siege") }
        if analysis.objectiveControlScore < 5 { suggestions.append("Consider a jungler for objective control") }
        return suggestions
    }
}

// MARK: - Comfort Tracker
actor ComfortTracker {
    private var playHistory: [String: Int] = [:]

    func recordPlay(heroID: String) {
        playHistory[heroID, default: 0] += 1
    }

    func comfortLevel(for heroID: String) -> Double {
        let games = playHistory[heroID] ?? 0
        return min(10.0, Double(games) * 0.5 + 5.0)
    }
}

// MARK: - Array Extension
private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
