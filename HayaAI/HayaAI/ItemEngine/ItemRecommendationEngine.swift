import Foundation

// MARK: - Item Recommendation Engine
actor ItemRecommendationEngine: ItemEngineProtocol {

    // MARK: - Item Database (embedded for MVP)
    private let itemDatabase: ItemDatabase

    init() {
        self.itemDatabase = ItemDatabase()
    }

    // MARK: - ItemEngineProtocol

    func recommendBuild(
        for hero: Hero,
        against enemyHeroes: [Hero],
        situation: BuildSituation
    ) async throws -> SuggestedBuild {
        var build = SuggestedBuild()

        // Core items from hero's preferred build
        build.coreItems = hero.preferredItems.prefix(4).map { $0 }
        build.boots = hero.preferredItems.first { $0.name.lowercased().contains("boots") }

        // Situational items based on enemy composition
        let counterItems = await computeCounterItems(against: enemyHeroes)

        // Adjust for build situation
        switch situation {
        case .standard:
            build.coreItems = Array(hero.preferredItems.prefix(4))
            build.situationalItems = hero.situationalItems

        case .snowball:
            // Prioritise damage items
            build.coreItems = hero.preferredItems.filter { $0.category == .physical || $0.category == .magic }
            build.situationalItems = []

        case .comeback:
            // Add survivability
            let defenseItems = itemDatabase.defenseItems
            build.situationalItems = Array(defenseItems.prefix(2))

        case .lateGame:
            build.coreItems = hero.preferredItems
            build.situationalItems = hero.situationalItems

        case .antiHeal:
            let antiHealItems = itemDatabase.antiHealItems(for: hero.damageType)
            build.coreItems = hero.preferredItems.prefix(3).map { $0 }
            build.coreItems.append(contentsOf: antiHealItems)
        }

        build.counterItems = counterItems
        build.buildExplanation = generateBuildExplanation(
            hero: hero,
            situation: situation,
            enemies: enemyHeroes
        )

        return build
    }

    func counterBuildItems(against enemyHeroes: [Hero]) async throws -> [Item] {
        return await computeCounterItems(against: enemyHeroes)
    }

    // MARK: - Private Helpers

    private func computeCounterItems(against enemies: [Hero]) async -> [Item] {
        var items: [Item] = []

        let hasMagic = enemies.contains { $0.damageType == .magic || $0.damageType == .hybrid }
        let hasPhysical = enemies.contains { $0.damageType == .physical || $0.damageType == .hybrid }
        let hasSustain = enemies.contains { $0.sustain > 7.0 }
        let hasHighBurst = enemies.contains { $0.burst > 8.0 }

        if hasMagic { items.append(contentsOf: itemDatabase.magicDefenseItems) }
        if hasPhysical { items.append(contentsOf: itemDatabase.physicalDefenseItems) }
        if hasSustain { items.append(contentsOf: itemDatabase.antiHealItems(for: .physical)) }
        if hasHighBurst { items.append(itemDatabase.immortality) }

        return Array(Set(items)).prefix(3).map { $0 }
    }

    private func generateBuildExplanation(hero: Hero, situation: BuildSituation, enemies: [Hero]) -> String {
        var explanation = "This build focuses on \(hero.primaryRole.rawValue) playstyle. "
        switch situation {
        case .standard: explanation += "Balanced damage and defense."
        case .snowball: explanation += "Maximize damage to close out early leads."
        case .comeback: explanation += "Extra survivability to stay alive in a losing game."
        case .lateGame: explanation += "Full power build for extended games."
        case .antiHeal: explanation += "Anti-heal counters their sustain-heavy composition."
        }
        return explanation
    }
}

// MARK: - Item Database
struct ItemDatabase: Sendable {
    let defenseItems: [Item] = [
        Item(id: "immortality", name: "Immortality", category: .defense, description: "Revives on death"),
        Item(id: "antique_cuirass", name: "Antique Cuirass", category: .defense, description: "-8% enemy ATK per hit"),
        Item(id: "athenas_shield", name: "Athena's Shield", category: .defense, description: "Magic shield every 30s"),
        Item(id: "oracle", name: "Oracle", category: .defense, description: "+30% shield/regen"),
        Item(id: "dominance_ice", name: "Dominance Ice", category: .defense, description: "-30% AS aura")
    ]

    let magicDefenseItems: [Item] = [
        Item(id: "athenas_shield", name: "Athena's Shield", category: .defense, description: "Magic shield every 30s"),
        Item(id: "radiant_armor", name: "Radiant Armor", category: .defense, description: "Stacks magic defense")
    ]

    let physicalDefenseItems: [Item] = [
        Item(id: "antique_cuirass", name: "Antique Cuirass", category: .defense, description: "-8% enemy ATK per hit"),
        Item(id: "brute_force", name: "Brute Force Breastplate", category: .defense, description: "Stack physical defense")
    ]

    let immortality = Item(id: "immortality", name: "Immortality", category: .defense, description: "Revives on death")

    func antiHealItems(for damageType: DamageType) -> [Item] {
        switch damageType {
        case .physical:
            return [Item(id: "sea_halberd", name: "Sea Halberd", category: .physical, description: "-50% healing")]
        case .magic:
            return [Item(id: "necklace_of_durance", name: "Necklace of Durance", category: .magic, description: "-50% healing")]
        default:
            return [
                Item(id: "sea_halberd", name: "Sea Halberd", category: .physical, description: "-50% healing"),
                Item(id: "necklace_of_durance", name: "Necklace of Durance", category: .magic, description: "-50% healing")
            ]
        }
    }
}
