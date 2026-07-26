import Foundation
import CoreGraphics

// MARK: - Game Session Phase
enum GameSessionPhase: String, Codable, CaseIterable, Sendable {
    case idle = "Idle"
    case draft = "Draft"
    case loading = "Loading"
    case earlyGame = "Early Game"
    case midGame = "Mid Game"
    case lateGame = "Late Game"
    case gameOver = "Game Over"

    var isInGame: Bool {
        [.earlyGame, .midGame, .lateGame].contains(self)
    }

    var minuteRange: ClosedRange<Int> {
        switch self {
        case .earlyGame: return 0...8
        case .midGame: return 9...15
        case .lateGame: return 16...60
        default: return 0...60
        }
    }
}

// MARK: - Objective State
enum ObjectiveStatus: String, Codable, Sendable {
    case alive = "Alive"
    case dead = "Dead"
    case respawning = "Respawning"
    case unknown = "Unknown"
}

struct ObjectiveState: Codable, Equatable, Sendable {
    var turtle: ObjectiveTimer = ObjectiveTimer(type: .turtle)
    var lord: ObjectiveTimer = ObjectiveTimer(type: .lord)
    var friendlyTowers: [TowerState] = TowerState.initialLayout(team: .friendly)
    var enemyTowers: [TowerState] = TowerState.initialLayout(team: .enemy)
}

struct ObjectiveTimer: Codable, Equatable, Sendable {
    let type: Objective
    var status: ObjectiveStatus = .alive
    var respawnAt: Date? = nil
    var secondsUntilSpawn: Int? = nil
    var lastKilledAt: Date? = nil
    var lastKilledBy: DraftTurn? = nil

    var isAboutToSpawn: Bool {
        guard let secs = secondsUntilSpawn else { return false }
        return secs <= 30 && secs > 0
    }

    var isSpawning: Bool {
        secondsUntilSpawn == 0
    }
}

struct TowerState: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let team: DraftTurn
    let lane: TowerLane
    let tier: Int      // 1 = outer, 2 = inner, 3 = inhibitor
    var isAlive: Bool = true
    var destroyedAt: Date? = nil

    enum TowerLane: String, Codable, Sendable { case top, mid, bottom, base }

    static func initialLayout(team: DraftTurn) -> [TowerState] {
        var towers: [TowerState] = []
        let prefix = "\(team.rawValue.lowercased())"
        for lane in [TowerLane.top, .mid, .bottom] {
            for tier in 1...3 {
                towers.append(TowerState(id: "\(prefix)_\(lane.rawValue)_\(tier)", team: team, lane: lane, tier: tier))
            }
        }
        towers.append(TowerState(id: "\(prefix)_base_1", team: team, lane: .base, tier: 1))
        towers.append(TowerState(id: "\(prefix)_base_2", team: team, lane: .base, tier: 2))
        return towers
    }
}

// MARK: - Kill Tracking
struct KillEvent: Identifiable, Codable, Sendable {
    let id: String
    let killerHero: String?
    let victimHero: String?
    let killerTeam: DraftTurn
    let gameTime: Int        // seconds
    let isFirstBlood: Bool
    let assistHeroes: [String]
    let occurredAt: Date
}

struct KillScore: Codable, Equatable, Sendable {
    var friendly: Int = 0
    var enemy: Int = 0
    var friendlyDeaths: Int = 0
    var enemyDeaths: Int = 0

    var killLead: Int { friendly - enemy }
    var isAhead: Bool { killLead > 0 }
    var isBehind: Bool { killLead < 0 }
    var isEven: Bool { killLead == 0 }
}

// MARK: - Gold & XP
struct EconomyState: Codable, Equatable, Sendable {
    var friendlyGold: Int = 0
    var enemyGold: Int = 0
    var goldLead: Int { friendlyGold - enemyGold }
    var isGoldAhead: Bool { goldLead > 500 }
    var isGoldBehind: Bool { goldLead < -500 }
    var isTurtlable: Bool { goldLead > -2000 }
}

// MARK: - Minimap Detection
struct MinimapState: Codable, Sendable {
    var detectedEnemyPositions: [EnemyPosition] = []
    var missingEnemies: [String] = []
    var visibleEnemies: [String] = []
    var lastUpdatedAt: Date = Date()
}

struct EnemyPosition: Identifiable, Codable, Sendable {
    let id: String
    var heroName: String?
    var normalizedPosition: CGPoint     // 0–1 relative to minimap
    var lane: HeroLane?
    var detectedAt: Date
    var confidence: Double
}

// MARK: - Player State
struct PlayerState: Codable, Equatable, Sendable {
    var heroName: String = ""
    var currentHP: Double = 1.0          // 0.0–1.0
    var currentMana: Double = 1.0
    var gold: Int = 0
    var level: Int = 1
    var isAlive: Bool = true
    var deathTimerSeconds: Int? = nil
    var skill1Ready: Bool = true
    var skill2Ready: Bool = true
    var ultReady: Bool = true
    var spellReady: Bool = true
    var currentItems: [String] = []
}

// MARK: - Main Live Game State
struct LiveGameState: Codable, Equatable, Sendable {
    var sessionPhase: GameSessionPhase = .idle
    var gameTimeSeconds: Int = 0
    var killScore: KillScore = KillScore()
    var economy: EconomyState = EconomyState()
    var objectives: ObjectiveState = ObjectiveState()
    var minimap: MinimapState = MinimapState()
    var playerState: PlayerState = PlayerState()
    var activeAlerts: [CoachAlert] = []
    var currentAdvice: String = ""
    var activeObjectiveAdvice: String = ""
    var detectionConfidence: Double = 0.0
    var lastFrameProcessedAt: Date = Date()
    var isFirstBloodAchieved: Bool = false

    var gameTimeFormatted: String {
        let minutes = gameTimeSeconds / 60
        let seconds = gameTimeSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var gamePhaseLabel: String { sessionPhase.rawValue }

    static func == (lhs: LiveGameState, rhs: LiveGameState) -> Bool {
        lhs.sessionPhase == rhs.sessionPhase &&
        lhs.gameTimeSeconds == rhs.gameTimeSeconds &&
        lhs.killScore == rhs.killScore &&
        lhs.economy == rhs.economy &&
        lhs.playerState == rhs.playerState
    }
}

// MARK: - Coach Alert
struct CoachAlert: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var type: AlertType
    var priority: AlertPriority
    var message: String
    var detail: String?
    var action: String?
    var triggeredAt: Date
    var expiresAt: Date
    var hasBeenDismissed: Bool = false

    var isExpired: Bool { Date() > expiresAt }
    var isActive: Bool { !isExpired && !hasBeenDismissed }
}

enum AlertType: String, Codable, CaseIterable, Sendable {
    // Objectives
    case turtleSpawning = "TurtleSpawning"
    case turtleAlive = "TurtleAlive"
    case lordSpawning = "LordSpawning"
    case lordAlive = "LordAlive"
    case objectiveStolenRisk = "ObjectiveStolenRisk"

    // Enemy
    case enemyMissing = "EnemyMissing"
    case gankRisk = "GankRisk"
    case enemyInvisible = "EnemyInvisible"
    case enemyGrouping = "EnemyGrouping"

    // Advantages
    case killAdvantage = "KillAdvantage"
    case goldAdvantage = "GoldAdvantage"
    case pushOpportunity = "PushOpportunity"
    case rotateNow = "RotateNow"
    case baseRace = "BaseRace"

    // Defensive
    case deathTimerPush = "DeathTimerPush"
    case lowHP = "LowHP"
    case backOff = "BackOff"

    // Rotation
    case rotateToTurtle = "RotateToTurtle"
    case groupUp = "GroupUp"
    case splitPush = "SplitPush"

    // Game state
    case firstBloodChance = "FirstBloodChance"
    case powerSpikeReached = "PowerSpikeReached"
    case teamfightStarting = "TeamfightStarting"
    case gameOver = "GameOver"

    var icon: String {
        switch self {
        case .turtleSpawning, .turtleAlive: return "tortoise.fill"
        case .lordSpawning, .lordAlive: return "crown.fill"
        case .objectiveStolenRisk: return "exclamationmark.shield.fill"
        case .enemyMissing, .enemyInvisible: return "eye.slash.fill"
        case .gankRisk: return "exclamationmark.triangle.fill"
        case .enemyGrouping: return "person.3.fill"
        case .killAdvantage: return "bolt.fill"
        case .goldAdvantage: return "dollarsign.circle.fill"
        case .pushOpportunity: return "arrow.right.circle.fill"
        case .rotateNow: return "arrow.triangle.2.circlepath"
        case .baseRace: return "house.fill"
        case .deathTimerPush: return "timer"
        case .lowHP: return "heart.slash.fill"
        case .backOff: return "hand.raised.fill"
        case .rotateToTurtle, .groupUp: return "figure.walk"
        case .splitPush: return "arrow.left.arrow.right"
        case .firstBloodChance: return "drop.fill"
        case .powerSpikeReached: return "star.fill"
        case .teamfightStarting: return "burst.fill"
        case .gameOver: return "flag.checkered"
        }
    }
}

enum AlertPriority: Int, Codable, CaseIterable, Sendable, Comparable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    var color: String {
        switch self {
        case .low: return "#4CAF50"
        case .medium: return "#FF9800"
        case .high: return "#F44336"
        case .critical: return "#9C27B0"
        }
    }
}

// MARK: - In-Game Frame Analysis
struct InGameFrameAnalysis: Sendable {
    let frameID: String = UUID().uuidString
    let gameTimestamp: Int?         // game clock in seconds
    let killScoreDetected: KillScore?
    let goldDetected: EconomyState?
    let objectiveHP: Double?        // 0–1 when visible
    let enemyPositions: [EnemyPosition]
    let playerHP: Double?
    let playerMana: Double?
    let processingMs: Double
    let rawTexts: [DetectedText]
    let frameTimestamp: CMTimeValue
    let sessionPhase: GameSessionPhase
}
