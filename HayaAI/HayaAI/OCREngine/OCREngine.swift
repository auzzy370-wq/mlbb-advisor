import Foundation
import Vision
import CoreGraphics

// MARK: - OCR Engine
/// Wraps Apple's Vision framework VNRecognizeTextRequest to extract
/// text from captured frames. Results are filtered and classified
/// to help the Draft State Manager interpret what is on screen.
actor OCREngine: OCREngineProtocol {

    // MARK: - Configuration
    struct Configuration: Sendable {
        var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
        var recognitionLanguages: [String] = ["en-US"]
        var usesLanguageCorrection: Bool = false
        var minimumTextHeight: Float = 0.02
        var customWords: [String] = []
    }

    private var configuration: Configuration
    private let heroNameMatcher: HeroNameMatcher
    private let phaseKeywords: [String: DraftPhase] = [
        "ban": .banPhase1,
        "banning": .banPhase1,
        "ban phase": .banPhase1,
        "pick": .pickPhase1,
        "picking": .pickPhase1,
        "pick phase": .pickPhase1,
        "select": .pickPhase1,
        "hero selection": .pickPhase1
    ]
    private let timerPattern    = try! NSRegularExpression(pattern: #"^\d{1,2}$"#)
    private let clockPattern    = try! NSRegularExpression(pattern: #"^\d{1,2}:\d{2}$"#)
    private let killPattern     = try! NSRegularExpression(pattern: #"^\d{1,2}\s*[:/\-]\s*\d{1,2}$"#)

    init(configuration: Configuration = Configuration(), heroNames: [String]) {
        self.configuration = configuration
        self.heroNameMatcher = HeroNameMatcher(heroNames: heroNames)
    }

    // MARK: - Public API

    func recognizeText(in image: CGImage, roi: CGRect?) async throws -> [DetectedText] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = buildTextRequest(roi: roi)
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let results = (request.results ?? []).compactMap { obs -> DetectedText? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let category = self.classify(text: candidate.string)
                    return DetectedText(
                        text: candidate.string.trimmingCharacters(in: .whitespacesAndNewlines),
                        boundingBox: obs.boundingBox,
                        confidence: Double(candidate.confidence),
                        category: category
                    )
                }
                continuation.resume(returning: results)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func recognizeHeroName(in image: CGImage, roi: CGRect) async throws -> String? {
        let texts = try await recognizeText(in: image, roi: roi)
        let candidates = texts.filter { $0.confidence > 0.55 }.map { $0.text }
        return heroNameMatcher.bestMatch(for: candidates)
    }

    func recognizeTimer(in image: CGImage, roi: CGRect) async throws -> Int? {
        let texts = try await recognizeText(in: image, roi: roi)
        for text in texts {
            let trimmed = text.text.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if timerPattern.firstMatch(in: trimmed, range: range) != nil,
               let value = Int(trimmed), value >= 0, value <= 99 {
                return value
            }
        }
        return nil
    }

    func recognizePhase(in image: CGImage, roi: CGRect) async throws -> DraftPhase? {
        let texts = try await recognizeText(in: image, roi: roi)
        let combined = texts.map { $0.text.lowercased() }.joined(separator: " ")
        for (keyword, phase) in phaseKeywords {
            if combined.contains(keyword) {
                return phase
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    private func buildTextRequest(roi: CGRect?) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = configuration.recognitionLevel
        request.recognitionLanguages = configuration.recognitionLanguages
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        request.minimumTextHeight = configuration.minimumTextHeight
        if !configuration.customWords.isEmpty {
            request.customWords = configuration.customWords
        }
        if let roi {
            request.regionOfInterest = roi
        }
        return request
    }

    private func classify(text: String) -> TextCategory {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        let range = NSRange(lower.startIndex..., in: lower)

        // MM:SS game clock — must check before timerPattern (which is also \d+)
        if clockPattern.firstMatch(in: lower, range: range) != nil {
            return .gameClock
        }
        // Draft countdown (single number 1-99)
        if timerPattern.firstMatch(in: lower, range: range) != nil {
            return .timer
        }
        // Kill score "N : M" at top of HUD — check before heroName to avoid false match
        if killPattern.firstMatch(in: lower, range: range) != nil {
            return .killScore
        }
        for keyword in phaseKeywords.keys where lower.contains(keyword) {
            return .phase
        }
        if heroNameMatcher.isHeroName(lower) {
            return .heroName
        }
        if lower.hasPrefix("patch") || lower.contains("patch") {
            return .patchVersion
        }
        for role in HeroRole.allCases where lower.contains(role.rawValue.lowercased()) {
            return .role
        }
        return .unknown
    }

    // MARK: - Update Config
    func updateHeroNames(_ names: [String]) {
        heroNameMatcher.update(names: names)
    }
}

// MARK: - Hero Name Matcher
/// Matches OCR output against the known hero name list with fuzzy tolerance
/// so that common Vision errors (transposed chars, missing apostrophes, extra
/// spaces, slight mis-reads) still resolve to the correct hero name.
final class HeroNameMatcher: @unchecked Sendable {
    private var lowerNames: [String: String] = [:]   // normalised → original
    private var normalised: [String: String] = [:]   // fully-stripped → original

    init(heroNames: [String]) { update(names: heroNames) }

    func update(names: [String]) {
        lowerNames   = Dictionary(uniqueKeysWithValues: names.map { ($0.lowercased(), $0) })
        normalised   = Dictionary(uniqueKeysWithValues: names.map { (strip($0), $0) })
    }

    // MARK: Exact + fuzzy public API

    func isHeroName(_ text: String) -> Bool {
        bestMatch(for: [text]) != nil
    }

    func bestMatch(for candidates: [String]) -> String? {
        for raw in candidates {
            // 1. Exact lowercase
            if let m = lowerNames[raw.lowercased()] { return m }
            // 2. Stripped (remove non-alphanum, spaces → "") exact
            let s = strip(raw)
            if let m = normalised[s] { return m }
            // 3. Levenshtein distance ≤ 2 on stripped strings
            if let m = closestMatch(stripped: s) { return m }
        }
        return nil
    }

    // MARK: Private

    /// Remove all non-letter, non-digit characters and lowercase.
    private func strip(_ s: String) -> String {
        s.lowercased()
         .unicodeScalars
         .filter { CharacterSet.letters.union(.decimalDigits).contains($0) }
         .map { String($0) }
         .joined()
    }

    private func closestMatch(stripped: String) -> String? {
        guard stripped.count >= 3 else { return nil }
        let maxDist = stripped.count <= 5 ? 1 : 2
        var best: (dist: Int, name: String)? = nil
        for (key, original) in normalised {
            guard abs(key.count - stripped.count) <= maxDist else { continue }
            let d = levenshtein(stripped, key)
            if d <= maxDist {
                if best == nil || d < best!.dist { best = (d, original) }
            }
        }
        return best?.name
    }

    /// Standard iterative Levenshtein distance.
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1] ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }
        return dp[m][n]
    }
}
