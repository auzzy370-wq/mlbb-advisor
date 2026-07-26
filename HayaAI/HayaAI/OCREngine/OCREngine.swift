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
    private let timerPattern = try! NSRegularExpression(pattern: #"^\d{1,2}$"#)

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

        if timerPattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return .timer
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
/// Fast fuzzy-match of OCR output against the known hero name list.
final class HeroNameMatcher: @unchecked Sendable {
    private var heroNames: Set<String> = []
    private var lowerNames: [String: String] = [:]

    init(heroNames: [String]) {
        update(names: heroNames)
    }

    func update(names: [String]) {
        heroNames = Set(names)
        lowerNames = Dictionary(uniqueKeysWithValues: names.map { ($0.lowercased(), $0) })
    }

    func isHeroName(_ text: String) -> Bool {
        lowerNames[text.lowercased()] != nil
    }

    func bestMatch(for candidates: [String]) -> String? {
        for candidate in candidates {
            let lower = candidate.lowercased()
            if let match = lowerNames[lower] { return match }
        }
        // Fuzzy: try substring match
        for candidate in candidates {
            let lower = candidate.lowercased()
            for (key, original) in lowerNames where key.contains(lower) || lower.contains(key) {
                return original
            }
        }
        return nil
    }
}
