import Foundation

// MARK: - User Profile
struct UserProfile: Codable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var email: String
    var avatarURL: String?
    var favoriteHeroes: [String] = []
    var preferredRoles: [HeroRole] = []
    var preferredLanes: [HeroLane] = []
    var matchHistory: [MatchRecord] = []
    var heroWinRates: [String: WinRateRecord] = [:]
    var roleWinRates: [HeroRole: WinRateRecord] = [:]
    var recommendationAccuracy: Double = 0.0
    var totalDraftsAnalyzed: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPremium: Bool = false
    var settings: UserSettings = UserSettings()

    /// A local guest profile used when Firebase is not configured (sideloaded / offline).
    static var guest: UserProfile {
        UserProfile(id: "guest", displayName: "Player", email: "")
    }
    var isGuest: Bool { id == "guest" }
}

// MARK: - Match Record
struct MatchRecord: Codable, Identifiable, Sendable {
    let id: String
    var heroID: String
    var heroName: String
    var role: HeroRole
    var lane: HeroLane
    var result: MatchResult
    var kda: KDA
    var draftRecommendation: String?
    var followedRecommendation: Bool = false
    var playedAt: Date
    var patchVersion: String
    var rank: String?
}

enum MatchResult: String, Codable, Sendable {
    case win = "Win"
    case loss = "Loss"
    case unknown = "Unknown"
}

struct KDA: Codable, Sendable {
    var kills: Int = 0
    var deaths: Int = 0
    var assists: Int = 0

    var ratio: Double {
        deaths == 0 ? Double(kills + assists) : Double(kills + assists) / Double(deaths)
    }
}

// MARK: - Win Rate Record
struct WinRateRecord: Codable, Sendable {
    var wins: Int = 0
    var losses: Int = 0
    var total: Int { wins + losses }
    var winRate: Double { total == 0 ? 0 : Double(wins) / Double(total) }
}

// MARK: - User Settings
struct UserSettings: Codable, Sendable {
    var enableHaptics: Bool = true
    var enableSounds: Bool = false
    var showConfidenceBars: Bool = true
    var showDetailedScores: Bool = false
    var preferredDraftSide: DraftTurn = .friendly
    var autoDetectDraft: Bool = true
    var notificationFrequency: NotificationFrequency = .normal
    var dataCollection: Bool = true
    var overlayOpacity: Double = 0.85
    var recommendationCount: Int = 5
}

enum NotificationFrequency: String, Codable, CaseIterable, Sendable {
    case off = "Off"
    case minimal = "Minimal"
    case normal = "Normal"
    case all = "All"
}
