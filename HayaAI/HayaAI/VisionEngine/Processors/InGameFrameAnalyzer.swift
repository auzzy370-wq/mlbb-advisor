import Foundation
import Vision
import CoreGraphics

// MARK: - In-Game Frame Analyzer
/// Processes live game frames to extract game clock, kill score, gold,
/// objective HP, minimap positions, and player HP/mana.
/// Separate from the draft VisionEngine so both can be active simultaneously.
actor InGameFrameAnalyzer {

    // MARK: - Sub-analyzers
    private let clockDetector: GameClockDetector
    private let killFeedDetector: KillFeedDetector
    private let minimapAnalyzer: MinimapAnalyzer
    private let hpBarDetector: HPBarDetector
    private let goldDetector: GoldDetector
    private let sessionClassifier: GameSessionClassifier

    // MARK: - State
    private var lastPhase: GameSessionPhase = .idle
    private var lastProcessedAt: Date = .distantPast
    private let processingIntervalSeconds: Double = 1.0 / 10.0   // 10fps in-game

    init() {
        clockDetector = GameClockDetector()
        killFeedDetector = KillFeedDetector()
        minimapAnalyzer = MinimapAnalyzer()
        hpBarDetector = HPBarDetector()
        goldDetector = GoldDetector()
        sessionClassifier = GameSessionClassifier()
    }

    // MARK: - Main entry point

    func analyze(_ image: CGImage, timestamp: CMTimeValue) async -> InGameFrameAnalysis {
        let startTime = Date()

        // Session / phase classification first – drives which ROIs to scan
        let phase = await sessionClassifier.classify(image: image)

        async let gameClock = clockDetector.detect(in: image)
        async let kills = killFeedDetector.detect(in: image)
        async let minimap = minimapAnalyzer.detect(in: image)
        async let bars = hpBarDetector.detect(in: image)
        async let gold = goldDetector.detect(in: image)

        let (clock, killScore, enemies, (hp, mana), economy) = await (gameClock, kills, minimap, bars, gold)

        let processingMs = Date().timeIntervalSince(startTime) * 1000
        lastPhase = phase

        return InGameFrameAnalysis(
            gameTimestamp: clock,
            killScoreDetected: killScore,
            goldDetected: economy,
            objectiveHP: nil,
            enemyPositions: enemies,
            playerHP: hp,
            playerMana: mana,
            processingMs: processingMs,
            rawTexts: [],
            frameTimestamp: timestamp,
            sessionPhase: phase
        )
    }

    func updateProcessingRate(fps: Int) {
        // processingIntervalSeconds = 1.0 / Double(fps)
    }
}

// MARK: - Game Clock Detector
/// Reads the game clock (e.g. "08:32") from the top-center of the screen.
actor GameClockDetector {

    private let clockROI = CGRect(x: 0.43, y: 0.0, width: 0.14, height: 0.07)
    private let timePattern = try! NSRegularExpression(pattern: #"(\d{1,2}):(\d{2})"#)

    func detect(in image: CGImage) async -> Int? {
        guard let cropped = image.cropping(to: pixelRect(clockROI, in: image)) else { return nil }
        let texts = try? await performOCR(on: cropped)
        for text in texts ?? [] {
            if let seconds = parseTime(text) { return seconds }
        }
        return nil
    }

    private func parseTime(_ text: String) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = timePattern.firstMatch(in: text, range: range),
              let mRange = Range(match.range(at: 1), in: text),
              let sRange = Range(match.range(at: 2), in: text),
              let minutes = Int(text[mRange]),
              let seconds = Int(text[sRange])
        else { return nil }
        return minutes * 60 + seconds
    }
}

// MARK: - Kill Feed Detector
/// Reads the kill scoreline from the top of the HUD.
actor KillFeedDetector {

    private let scoreROI = CGRect(x: 0.35, y: 0.0, width: 0.30, height: 0.06)
    private let scorePattern = try! NSRegularExpression(pattern: #"(\d+)\s*[-–]\s*(\d+)"#)

    func detect(in image: CGImage) async -> KillScore? {
        guard let cropped = image.cropping(to: pixelRect(scoreROI, in: image)) else { return nil }
        let texts = try? await performOCR(on: cropped)
        for text in texts ?? [] {
            if let score = parseScore(text) { return score }
        }
        return nil
    }

    private func parseScore(_ text: String) -> KillScore? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = scorePattern.firstMatch(in: text, range: range),
              let aRange = Range(match.range(at: 1), in: text),
              let bRange = Range(match.range(at: 2), in: text),
              let a = Int(text[aRange]),
              let b = Int(text[bRange])
        else { return nil }
        return KillScore(friendly: a, enemy: b)
    }
}

// MARK: - Minimap Analyzer
/// Detects enemy hero indicators on the minimap.
/// Uses colour-based detection (enemy dot colour = red) against the minimap ROI.
actor MinimapAnalyzer {

    // Minimap is in the bottom-right corner in MLBB
    private let minimapROI = CGRect(x: 0.72, y: 0.60, width: 0.28, height: 0.40)

    func detect(in image: CGImage) async -> [EnemyPosition] {
        // Production: use CoreImage CIAreaHistogram / colour filter to find red dots
        // MVP: returns empty – scaffold in place for CoreML expansion
        return []
    }

    func enemiesInLane(_ positions: [EnemyPosition]) -> [HeroLane: [EnemyPosition]] {
        var result: [HeroLane: [EnemyPosition]] = [:]
        for pos in positions {
            // Map normalised minimap X/Y to approximate lane
            let lane = laneForPosition(pos.normalizedPosition)
            result[lane, default: []].append(pos)
        }
        return result
    }

    private func laneForPosition(_ pt: CGPoint) -> HeroLane {
        if pt.x < 0.3 && pt.y > 0.6 { return .exp }
        if pt.x > 0.6 && pt.y < 0.4 { return .gold }
        if abs(pt.x - 0.5) < 0.2 && abs(pt.y - 0.5) < 0.2 { return .mid }
        return .jungle
    }
}

// MARK: - HP Bar Detector
/// Reads the player's HP and mana percentage from the bottom-center HUD.
actor HPBarDetector {

    private let hpROI   = CGRect(x: 0.35, y: 0.90, width: 0.30, height: 0.04)
    private let manaROI = CGRect(x: 0.35, y: 0.94, width: 0.30, height: 0.03)

    func detect(in image: CGImage) async -> (hp: Double?, mana: Double?) {
        // Production: analyse bar fill ratio using CoreImage
        // or OCR the numeric HP value if the HUD shows it as text
        return (nil, nil)
    }
}

// MARK: - Gold Detector
/// Reads the player's current gold from the bottom-center HUD.
actor GoldDetector {

    private let goldROI = CGRect(x: 0.44, y: 0.88, width: 0.12, height: 0.05)
    private let numberPattern = try! NSRegularExpression(pattern: #"\d{3,6}"#)

    func detect(in image: CGImage) async -> EconomyState? {
        guard let cropped = image.cropping(to: pixelRect(goldROI, in: image)) else { return nil }
        let texts = try? await performOCR(on: cropped)
        for text in texts ?? [] {
            let range = NSRange(text.startIndex..., in: text)
            if let match = numberPattern.firstMatch(in: text, range: range),
               let r = Range(match.range, in: text),
               let gold = Int(text[r]) {
                return EconomyState(friendlyGold: gold, enemyGold: 0)
            }
        }
        return nil
    }
}

// MARK: - Game Session Classifier
/// Determines which phase of the game session we're in based on visual cues.
actor GameSessionClassifier {

    func classify(image: CGImage) async -> GameSessionPhase {
        // Heuristic: look for game clock to determine if we're in-game
        // A draft board presence means draft phase; a black screen means loading
        // In production: use scene-classification CoreML model
        return .earlyGame
    }

    nonisolated func detectFromClock(seconds: Int?) -> GameSessionPhase {
        guard let s = seconds else { return .earlyGame }
        switch s {
        case 0...480:   return .earlyGame
        case 481...900: return .midGame
        default:        return .lateGame
        }
    }
}

// MARK: - Shared OCR helper (file-scope utility)
private func performOCR(on image: CGImage) async throws -> [String] {
    return try await withCheckedThrowingContinuation { continuation in
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            let strings = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            continuation.resume(returning: strings)
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

private func pixelRect(_ normalised: CGRect, in image: CGImage) -> CGRect {
    CGRect(
        x: normalised.minX * CGFloat(image.width),
        y: normalised.minY * CGFloat(image.height),
        width: normalised.width * CGFloat(image.width),
        height: normalised.height * CGFloat(image.height)
    )
}
