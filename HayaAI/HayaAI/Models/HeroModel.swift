import Foundation

// MARK: - Hero Role
enum HeroRole: String, Codable, CaseIterable, Sendable {
    case tank = "Tank"
    case fighter = "Fighter"
    case assassin = "Assassin"
    case mage = "Mage"
    case marksman = "Marksman"
    case support = "Support"
    case jungler = "Jungler"
    case roamer = "Roamer"
}

// MARK: - Hero Lane
enum HeroLane: String, Codable, CaseIterable, Sendable {
    case exp = "EXP"
    case gold = "Gold"
    case mid = "Mid"
    case jungle = "Jungle"
    case roam = "Roam"
    case all = "All"
}

// MARK: - Damage Type
enum DamageType: String, Codable, CaseIterable, Sendable {
    case physical = "Physical"
    case magic = "Magic"
    case hybrid = "Hybrid"
    case trueDamage = "True"
}

// MARK: - Battle Spell
enum BattleSpell: String, Codable, CaseIterable, Sendable {
    case execute = "Execute"
    case retribution = "Retribution"
    case flicker = "Flicker"
    case aegis = "Aegis"
    case inspire = "Inspire"
    case sprint = "Sprint"
    case vengeance = "Vengeance"
    case petrify = "Petrify"
    case flameshot = "Flameshot"
    case arrival = "Arrival"
    case healing = "Healing"
    case purify = "Purify"
    case stun = "Stun"
}

// MARK: - Emblem Type
enum EmblemType: String, Codable, CaseIterable, Sendable {
    case assassin = "Assassin"
    case fighter = "Fighter"
    case mage = "Mage"
    case marksman = "Marksman"
    case support = "Support"
    case tank = "Tank"
    case jungle = "Jungle"
    case common = "Common"
}

// MARK: - Hero Difficulty
enum HeroDifficulty: Int, Codable, CaseIterable, Sendable {
    case easy = 1
    case moderate = 2
    case hard = 3
    case extreme = 4

    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .extreme: return "Extreme"
        }
    }
}

// MARK: - Hero Stat (0.0 – 10.0)
typealias HeroStat = Double

// MARK: - Item
struct Item: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let category: ItemCategory
    let description: String?
}

enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case physical = "Physical"
    case magic = "Magic"
    case defense = "Defense"
    case movement = "Movement"
    case jungling = "Jungling"
    case roaming = "Roaming"
}

// MARK: - Talent
struct Talent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let tier: Int
}

// MARK: - Combo Step
struct ComboStep: Codable, Identifiable, Sendable {
    let id: String
    let order: Int
    let skill: String
    let note: String?
}

// MARK: - Power Spike
struct PowerSpike: Codable, Identifiable, Sendable {
    let id: String
    let phase: GamePhase
    let description: String
    let level: Int?
    let itemTrigger: String?
}

enum GamePhase: String, Codable, CaseIterable, Sendable {
    case early = "Early"
    case mid = "Mid"
    case late = "Late"
}

// MARK: - Hero Model
struct Hero: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let title: String?
    let imageURL: String?

    // Roles & Lane
    let primaryRole: HeroRole
    let secondaryRole: HeroRole?
    let primaryLane: HeroLane
    let secondaryLane: HeroLane?

    // Damage
    let damageType: DamageType

    // Difficulty
    let difficulty: HeroDifficulty

    // Stats (0.0 – 10.0)
    let earlyStrength: HeroStat
    let midStrength: HeroStat
    let lateStrength: HeroStat
    let mobility: HeroStat
    let crowdControl: HeroStat
    let burst: HeroStat
    let sustain: HeroStat
    let objectiveControl: HeroStat
    let waveClear: HeroStat
    let scaling: HeroStat

    // Matchups
    let strongAgainst: [String]
    let weakAgainst: [String]
    let counterHeroes: [String]
    let counteredBy: [String]

    // Build
    let preferredItems: [Item]
    let situationalItems: [Item]
    let counterItems: [Item]

    // Meta
    let bestSpell: BattleSpell
    let bestEmblem: EmblemType
    let talents: [Talent]
    let combos: [ComboStep]
    let rotationGuide: String
    let powerSpikes: [PowerSpike]

    // Draft & Meta
    let draftPriority: HeroStat
    let banPriority: HeroStat
    let metaScore: HeroStat
    let professionalPickRate: Double
    let professionalWinRate: Double
    let rankWinRate: Double

    // Computed
    var roles: [HeroRole] {
        [primaryRole, secondaryRole].compactMap { $0 }
    }

    var lanes: [HeroLane] {
        [primaryLane, secondaryLane].compactMap { $0 }
    }

    static func == (lhs: Hero, rhs: Hero) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
