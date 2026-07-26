import Foundation

// MARK: - In-Game Recommendation Models
// Everything the Live Coach panel shows the player during an actual match.

// MARK: - Build Step
/// One item in the recommended purchase sequence for the current game state.
struct BuildStep: Identifiable, Codable, Sendable {
    let id: String
    let order: Int                  // 1 = buy next
    let item: Item
    let reason: String              // why this item right now
    let isNextToBuy: Bool           // highlighted in the UI
    let isAlreadyOwned: Bool        // greyed out
    let costGold: Int
    let urgency: BuildUrgency

    enum BuildUrgency: String, Codable, Sendable {
        case core = "Core"          // always buy, in order
        case situational = "Sit."   // buy against this specific enemy
        case counter = "Counter"    // specifically counters an enemy hero/trait
        case optional = "Optional"
    }
}

// MARK: - Build Progression
/// Full ordered build for the player's hero, updated as the game state changes.
struct BuildProgression: Codable, Sendable {
    var heroName: String
    var steps: [BuildStep]
    var currentGold: Int
    var goldNeededForNext: Int
    var completionPercent: Double   // 0.0 – 1.0
    var buildNote: String
    var lastUpdatedAt: Date

    var nextStep: BuildStep? { steps.first { !$0.isAlreadyOwned } }
    var completedSteps: [BuildStep] { steps.filter { $0.isAlreadyOwned } }
    var remainingSteps: [BuildStep] { steps.filter { !$0.isAlreadyOwned } }
}

// MARK: - Target Recommendation
/// Who to attack first in a teamfight, with reasoning.
struct TargetRecommendation: Identifiable, Codable, Sendable {
    let id: String
    let heroName: String
    let heroRole: HeroRole
    let priority: TargetPriority     // 1 = highest priority
    let reason: String
    let howToKill: String            // skill combo / approach
    let dangerLevel: DangerLevel     // how dangerous this target is to you
    let canYouKill: Bool             // based on your hero vs theirs

    enum DangerLevel: String, Codable, Sendable {
        case safe = "Safe"
        case moderate = "Moderate"
        case dangerous = "Dangerous"
        case extreme = "Extreme"
    }
}

// MARK: - Skill Tip
/// When and how to use each skill in the current game context.
struct SkillTip: Identifiable, Codable, Sendable {
    let id: String
    let skillName: String           // "S1", "S2", "Ult", "Passive"
    let tip: String
    let useNow: Bool                // highlight = use this at current moment
    let cooldownNote: String?
    let comboHint: String?          // "S2 → S1 → Ult"
}

// MARK: - Rotation Advice
/// Where to go on the map right now, and why.
struct RotationAdvice: Codable, Sendable {
    var destination: RotationDestination
    var urgency: RotationUrgency
    var reason: String
    var timeWindow: String          // "Do this in the next 30 seconds"
    var afterRotation: String       // what to do after arriving
    var alternativeIfBehind: String

    enum RotationDestination: String, Codable, Sendable {
        case turtle = "Turtle Pit"
        case lord = "Lord Pit"
        case midLane = "Mid Lane"
        case expLane = "EXP Lane"
        case goldLane = "Gold Lane"
        case enemyJungle = "Enemy Jungle"
        case friendlyJungle = "Friendly Jungle"
        case base = "Base"
        case topTower = "Top Tower"
        case midTower = "Mid Tower"
        case botTower = "Bottom Tower"

        var icon: String {
            switch self {
            case .turtle: return "tortoise.fill"
            case .lord: return "crown.fill"
            case .midLane, .midTower: return "arrow.up"
            case .expLane, .topTower: return "arrow.up.left"
            case .goldLane, .botTower: return "arrow.down.right"
            case .enemyJungle: return "bolt.fill"
            case .friendlyJungle: return "leaf.fill"
            case .base: return "house.fill"
            }
        }
    }

    enum RotationUrgency: String, Codable, Sendable {
        case immediate = "Go now"
        case soon = "In ~30s"
        case whenReady = "When ready"
        case optional = "Optional"
    }
}

// MARK: - Matchup Tip
/// Real-time tip about the specific hero you're laning against or fighting.
struct MatchupTip: Identifiable, Codable, Sendable {
    let id: String
    let enemyHeroName: String
    let tip: String                 // how to beat them
    let avoidNote: String           // what not to do
    let counterSkill: String?       // which of your skills counters theirs
    let windowToFight: String       // "Fight after they use X skill"
}

// MARK: - Combo Reminder
/// A quick "do this combo now" nudge based on game context.
struct ComboReminder: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let steps: [String]             // ["S2", "Flash", "S1", "Ult"]
    let context: String             // "Use when initiating a gank"
    let triggerCondition: String    // "Enemy is isolated in bush"
}

// MARK: - In-Game Recommendation Package
/// Full snapshot of all in-game guidance for the current game state.
/// Re-computed whenever game state changes meaningfully.
struct InGameRecommendationPackage: Sendable {
    var heroName: String
    var sessionPhase: GameSessionPhase
    var buildProgression: BuildProgression
    var targetPriority: [TargetRecommendation]
    var currentRotation: RotationAdvice
    var skillTips: [SkillTip]
    var matchupTips: [MatchupTip]
    var comboReminder: ComboReminder?
    var powerSpikeNote: String
    var oneLineAdvice: String       // the single most important thing right now
    var generatedAt: Date
}
