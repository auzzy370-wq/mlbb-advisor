import Foundation
import Vision
import CoreImage
import CoreGraphics

// MARK: - Vision Engine
/// Central orchestrator for all computer-vision processing of captured frames.
/// Runs on a dedicated actor to ensure thread-safe access to its state.
actor VisionEngine: VisionEngineProtocol {

    // MARK: - State
    private(set) var isProcessing: Bool = false
    nonisolated var onFrameAnalyzed: ((FrameAnalysisResult) -> Void)?

    // MARK: - Dependencies
    private let ocrEngine: OCREngine
    private let heroDetector: HeroPortraitDetector
    private let phaseDetector: PhaseDetector
    private let timerDetector: TimerDetector

    // MARK: - Configuration
    private var configuration: VisionEngineConfiguration = VisionEngineConfiguration()

    // MARK: - Deduplication
    private var lastAnalysisResult: FrameAnalysisResult?
    private var lastAnalysisTime: Date = .distantPast

    // MARK: - Init
    init(heroNames: [String]) {
        self.ocrEngine = OCREngine(heroNames: heroNames)
        self.heroDetector = HeroPortraitDetector()
        self.phaseDetector = PhaseDetector()
        self.timerDetector = TimerDetector()
    }

    // MARK: - Protocol Methods

    func configure(with configuration: VisionEngineConfiguration) {
        self.configuration = configuration
    }

    func reset() {
        isProcessing = false
        lastAnalysisResult = nil
        lastAnalysisTime = .distantPast
    }

    func processFrame(_ pixelBuffer: CVPixelBufferRef, timestamp: CMTimeValue) async throws -> FrameAnalysisResult {
        // Deduplication guard
        let now = Date()
        let elapsed = now.timeIntervalSince(lastAnalysisTime)
        guard elapsed >= (1.0 / Double(configuration.targetFPS)) else {
            if let last = lastAnalysisResult { return last }
            throw VisionEngineError.throttled
        }

        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()

        guard let cgImage = createCGImage(from: pixelBuffer) else {
            throw VisionEngineError.invalidPixelBuffer
        }

        // Run all detections concurrently
        async let heroDetections = detectHeroes(in: cgImage)
        async let textDetections = detectText(in: cgImage)
        async let phase = detectPhase(in: cgImage)
        async let timer = detectTimer(in: cgImage)

        let (heroes, texts, detectedPhase, detectedTimer) = try await (
            heroDetections,
            textDetections,
            phase,
            timer
        )

        let processingTime = Date().timeIntervalSince(startTime) * 1000

        // Extract additional fields from text results
        let detectedTurn = extractTurn(from: texts)
        let detectedPatch = extractPatch(from: texts)

        let confidence = computeConfidence(
            heroes: heroes,
            texts: texts,
            phase: detectedPhase,
            timer: detectedTimer
        )

        let result = FrameAnalysisResult(
            detectedHeroes: heroes,
            detectedTexts: texts,
            detectedPhase: detectedPhase,
            detectedTimer: detectedTimer,
            detectedTurn: detectedTurn,
            detectedPatch: detectedPatch,
            processingTimeMs: processingTime,
            frameTimestamp: timestamp,
            overallConfidence: confidence
        )

        lastAnalysisResult = result
        lastAnalysisTime = now

        // Dispatch to observers on main queue
        let callback = onFrameAnalyzed
        Task { @MainActor in callback?(result) }

        return result
    }

    // MARK: - Private Detection Methods

    private func detectHeroes(in cgImage: CGImage) async throws -> [DetectedHero] {
        var heroes: [DetectedHero] = []

        for roi in configuration.regionsOfInterest where roi.purpose == .friendlyPicks || roi.purpose == .enemyPicks {
            let team: DraftTurn = roi.purpose == .friendlyPicks ? .friendly : .enemy

            // Crop to ROI
            let roiRect = CGRect(
                x: roi.normalizedRect.minX * CGFloat(cgImage.width),
                y: roi.normalizedRect.minY * CGFloat(cgImage.height),
                width: roi.normalizedRect.width * CGFloat(cgImage.width),
                height: roi.normalizedRect.height * CGFloat(cgImage.height)
            )

            if let croppedImage = cgImage.cropping(to: roiRect) {
                let detected = try await heroDetector.detectHeroes(in: croppedImage, team: team)
                heroes.append(contentsOf: detected)
            }
        }

        return heroes
    }

    private func detectText(in cgImage: CGImage) async throws -> [DetectedText] {
        guard configuration.enableOCR else { return [] }
        return try await ocrEngine.recognizeText(in: cgImage, roi: nil)
    }

    private func detectPhase(in cgImage: CGImage) async throws -> DraftPhase? {
        guard configuration.enablePhaseDetection else { return nil }
        for roi in configuration.regionsOfInterest where roi.purpose == .phaseIndicator {
            let phase = try await ocrEngine.recognizePhase(in: cgImage, roi: roi.normalizedRect)
            if let phase { return phase }
        }
        return try await phaseDetector.detect(in: cgImage)
    }

    private func detectTimer(in cgImage: CGImage) async throws -> Int? {
        guard configuration.enableTimerDetection else { return nil }
        for roi in configuration.regionsOfInterest where roi.purpose == .timer {
            let timer = try await ocrEngine.recognizeTimer(in: cgImage, roi: roi.normalizedRect)
            if let timer { return timer }
        }
        return nil
    }

    private func extractTurn(from texts: [DetectedText]) -> DraftTurn? {
        let combined = texts.map { $0.text.lowercased() }.joined(separator: " ")
        if combined.contains("your turn") || combined.contains("pick now") { return .friendly }
        if combined.contains("opponent") || combined.contains("enemy turn") { return .enemy }
        return nil
    }

    private func extractPatch(from texts: [DetectedText]) -> String? {
        for text in texts where text.category == .patchVersion {
            let matched = text.text
                .components(separatedBy: .whitespaces)
                .first { $0.first?.isNumber == true }
            return matched
        }
        return nil
    }

    private func computeConfidence(
        heroes: [DetectedHero],
        texts: [DetectedText],
        phase: DraftPhase?,
        timer: Int?
    ) -> Double {
        var score = 0.0
        var count = 0.0

        if !heroes.isEmpty {
            score += heroes.map { $0.confidence }.reduce(0, +) / Double(heroes.count)
            count += 1
        }
        if !texts.isEmpty {
            score += texts.map { $0.confidence }.reduce(0, +) / Double(texts.count)
            count += 1
        }
        if phase != nil { score += 0.8; count += 1 }
        if timer != nil { score += 0.9; count += 1 }

        return count > 0 ? score / count : 0.0
    }

    // MARK: - Pixel Buffer to CGImage
    private func createCGImage(from pixelBuffer: CVPixelBufferRef) -> CGImage? {
        // In production this uses CoreImage / CVPixelBuffer API.
        // Stubbed for compilation on Linux.
        return nil
    }
}

// MARK: - Vision Engine Errors
enum VisionEngineError: Error {
    case invalidPixelBuffer
    case processingFailed(String)
    case throttled
    case notConfigured
}
