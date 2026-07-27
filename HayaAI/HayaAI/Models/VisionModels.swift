import Foundation
import CoreGraphics

// MARK: - Detected Hero
struct DetectedHero: Identifiable, Sendable {
    let id: String = UUID().uuidString
    let name: String
    let boundingBox: CGRect
    let confidence: Double
    let team: DraftTurn
    let slotIndex: Int
    let detectionMethod: DetectionMethod
    let detectedAt: Date = Date()
}

// MARK: - Detected Text
struct DetectedText: Sendable {
    let text: String
    let boundingBox: CGRect
    let confidence: Double
    let category: TextCategory
    let detectedAt: Date = Date()
}

enum TextCategory: String, Sendable {
    case heroName    = "HeroName"
    case timer       = "Timer"      // draft countdown  (1-99)
    case gameClock   = "GameClock"  // in-game MM:SS
    case killScore   = "KillScore"  // e.g. "4 : 2"
    case phase       = "Phase"
    case role        = "Role"
    case lane        = "Lane"
    case patchVersion = "PatchVersion"
    case unknown     = "Unknown"
}

// MARK: - Detection Method
enum DetectionMethod: String, Sendable {
    case ocr = "OCR"
    case imageClassification = "ImageClassification"
    case templateMatching = "TemplateMatching"
    case combined = "Combined"
}

// MARK: - Frame Analysis Result
struct FrameAnalysisResult: Sendable {
    let frameID: String = UUID().uuidString
    let detectedHeroes: [DetectedHero]
    let detectedTexts: [DetectedText]
    let detectedPhase: DraftPhase?
    let detectedTimer: Int?
    /// In-game clock in seconds, parsed from MM:SS text (e.g. "08:32" → 512)
    let detectedGameClock: Int?
    /// Kill score parsed from "N : M" text at top of HUD
    let detectedKillScore: KillScore?
    let detectedTurn: DraftTurn?
    let detectedPatch: String?
    let processingTimeMs: Double
    let frameTimestamp: CMTimeValue
    let overallConfidence: Double

    var isEmpty: Bool {
        detectedHeroes.isEmpty && detectedTexts.isEmpty && detectedPhase == nil
    }
}

// CMTimeValue placeholder for non-Xcode build
typealias CMTimeValue = Int64

// MARK: - Region of Interest
struct VisionROI: Sendable {
    let name: String
    let normalizedRect: CGRect
    let purpose: ROIPurpose
}

enum ROIPurpose: String, Sendable {
    case friendlyBans = "FriendlyBans"
    case enemyBans = "EnemyBans"
    case friendlyPicks = "FriendlyPicks"
    case enemyPicks = "EnemyPicks"
    case timer = "Timer"
    case phaseIndicator = "PhaseIndicator"
    case heroHover = "HeroHover"
}

// MARK: - Standard Mobile Legends ROIs (1920x1080 normalized)
extension VisionROI {
    static let standardROIs: [VisionROI] = [
        VisionROI(
            name: "Friendly Picks",
            normalizedRect: CGRect(x: 0.0, y: 0.1, width: 0.2, height: 0.8),
            purpose: .friendlyPicks
        ),
        VisionROI(
            name: "Enemy Picks",
            normalizedRect: CGRect(x: 0.8, y: 0.1, width: 0.2, height: 0.8),
            purpose: .enemyPicks
        ),
        VisionROI(
            name: "Friendly Bans",
            normalizedRect: CGRect(x: 0.0, y: 0.0, width: 0.4, height: 0.15),
            purpose: .friendlyBans
        ),
        VisionROI(
            name: "Enemy Bans",
            normalizedRect: CGRect(x: 0.6, y: 0.0, width: 0.4, height: 0.15),
            purpose: .enemyBans
        ),
        VisionROI(
            name: "Timer",
            normalizedRect: CGRect(x: 0.45, y: 0.0, width: 0.1, height: 0.1),
            purpose: .timer
        ),
        VisionROI(
            name: "Phase Indicator",
            normalizedRect: CGRect(x: 0.35, y: 0.9, width: 0.3, height: 0.1),
            purpose: .phaseIndicator
        )
    ]
}
