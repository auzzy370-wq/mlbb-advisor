import Foundation

// MARK: - Strategy Model
struct DraftStrategy: Codable, Sendable {
    var earlyGamePlan: String = ""
    var midGamePlan: String = ""
    var lateGamePlan: String = ""
    var targetPriority: [TargetPriority] = []
    var objectivePriority: [ObjectivePriority] = []
    var turtleTiming: String = ""
    var lordTiming: String = ""
    var splitPushAdvice: String = ""
    var teamfightAdvice: String = ""
    var laneAssignments: [LaneAssignment] = []
    var winConditions: [String] = []
    var loseConditions: [String] = []
    var generatedAt: Date = Date()
}

// MARK: - Target Priority
struct TargetPriority: Codable, Identifiable, Sendable {
    let id: String
    let heroID: String
    let heroName: String
    let priority: PriorityLevel
    let reason: String
}

// MARK: - Objective Priority
struct ObjectivePriority: Codable, Identifiable, Sendable {
    let id: String
    let objective: Objective
    let timing: String
    let reason: String
    let priority: PriorityLevel
}

enum Objective: String, Codable, CaseIterable, Sendable {
    case turtle = "Turtle"
    case lord = "Lord"
    case tower = "Tower"
    case base = "Base"
    case jungle = "Jungle"
    case gold = "Gold"
}

enum PriorityLevel: Int, Codable, CaseIterable, Sendable {
    case low = 1
    case medium = 2
    case high = 3
    case critical = 4

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }

    var color: String {
        switch self {
        case .low: return "#4CAF50"
        case .medium: return "#FF9800"
        case .high: return "#F44336"
        case .critical: return "#9C27B0"
        }
    }
}

// MARK: - Lane Assignment
struct LaneAssignment: Codable, Identifiable, Sendable {
    let id: String
    let heroID: String
    let heroName: String
    let assignedLane: HeroLane
    let confidence: Double
    let reason: String
}
