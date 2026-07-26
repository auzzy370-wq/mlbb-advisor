import Foundation
import Combine

// MARK: - Draft Phase
enum DraftPhase: String, Codable, CaseIterable, Sendable {
    case notStarted = "Not Started"
    case banPhase1 = "Ban Phase 1"
    case pickPhase1 = "Pick Phase 1"
    case banPhase2 = "Ban Phase 2"
    case pickPhase2 = "Pick Phase 2"
    case completed = "Completed"
    case unknown = "Unknown"

    var isBanPhase: Bool { self == .banPhase1 || self == .banPhase2 }
    var isPickPhase: Bool { self == .pickPhase1 || self == .pickPhase2 }
}

// MARK: - Draft Turn
enum DraftTurn: String, Codable, Sendable {
    case friendly = "Friendly"
    case enemy = "Enemy"
    case unknown = "Unknown"
}

// MARK: - Slot Status
enum SlotStatus: String, Codable, Sendable {
    case empty = "Empty"
    case hovered = "Hovered"
    case locked = "Locked"
    case banned = "Banned"
}

// MARK: - Draft Slot
struct DraftSlot: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var heroID: String?
    var heroName: String?
    var status: SlotStatus
    var team: DraftTurn
    var position: Int

    static func empty(team: DraftTurn, position: Int) -> DraftSlot {
        DraftSlot(
            id: "\(team.rawValue)-\(position)",
            heroID: nil,
            heroName: nil,
            status: .empty,
            team: team,
            position: position
        )
    }
}

// MARK: - Team Composition Analysis
struct TeamCompositionAnalysis: Codable, Sendable {
    var frontlineScore: Double = 0
    var backlineScore: Double = 0
    var magicDamageScore: Double = 0
    var physicalDamageScore: Double = 0
    var burstScore: Double = 0
    var sustainScore: Double = 0
    var crowdControlScore: Double = 0
    var waveClearScore: Double = 0
    var objectiveControlScore: Double = 0
    var roamScore: Double = 0
    var scalingScore: Double = 0
    var earlyGameScore: Double = 0
    var lateGameScore: Double = 0
    var splitPushScore: Double = 0
    var diveScore: Double = 0
    var pokeScore: Double = 0
    var siegeScore: Double = 0
    var weaknesses: [String] = []
    var suggestions: [String] = []
}

// MARK: - Draft State (Main Model)
struct DraftState: Codable, Equatable, Sendable {
    var phase: DraftPhase = .notStarted
    var currentTurn: DraftTurn = .unknown
    var timer: Int = 30

    // Teams
    var friendlyPicks: [DraftSlot] = (0..<5).map { DraftSlot.empty(team: .friendly, position: $0) }
    var enemyPicks: [DraftSlot] = (0..<5).map { DraftSlot.empty(team: .enemy, position: $0) }

    // Bans
    var friendlyBans: [DraftSlot] = (0..<3).map {
        var s = DraftSlot.empty(team: .friendly, position: $0)
        s.status = .banned
        return s
    }
    var enemyBans: [DraftSlot] = (0..<3).map {
        var s = DraftSlot.empty(team: .enemy, position: $0)
        s.status = .banned
        return s
    }

    var hoveredHero: String? = nil
    var lockedHero: String? = nil
    var availableHeroes: [String] = []
    var currentRecommendation: [HeroRecommendation] = []
    var friendlyComposition: TeamCompositionAnalysis = TeamCompositionAnalysis()
    var enemyComposition: TeamCompositionAnalysis = TeamCompositionAnalysis()

    // Patch
    var patchVersion: String = "unknown"
    var detectedAt: Date = Date()
    var confidence: Double = 0.0

    // Derived
    var friendlyHeroIDs: [String] {
        friendlyPicks.compactMap { $0.heroID }
    }

    var enemyHeroIDs: [String] {
        enemyPicks.compactMap { $0.heroID }
    }

    var bannedHeroIDs: [String] {
        (friendlyBans + enemyBans).compactMap { $0.heroID }
    }

    var pickedHeroIDs: [String] {
        friendlyHeroIDs + enemyHeroIDs
    }

    var unavailableHeroIDs: [String] {
        pickedHeroIDs + bannedHeroIDs
    }

    var isMyTurn: Bool { currentTurn == .friendly }
    var isBanPhase: Bool { phase.isBanPhase }
    var isPickPhase: Bool { phase.isPickPhase }

    static func == (lhs: DraftState, rhs: DraftState) -> Bool {
        lhs.phase == rhs.phase &&
        lhs.currentTurn == rhs.currentTurn &&
        lhs.timer == rhs.timer &&
        lhs.friendlyPicks == rhs.friendlyPicks &&
        lhs.enemyPicks == rhs.enemyPicks &&
        lhs.friendlyBans == rhs.friendlyBans &&
        lhs.enemyBans == rhs.enemyBans &&
        lhs.hoveredHero == rhs.hoveredHero &&
        lhs.lockedHero == rhs.lockedHero
    }
}
