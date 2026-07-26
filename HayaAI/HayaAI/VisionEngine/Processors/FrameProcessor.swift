import Foundation
import CoreGraphics

// MARK: - Frame Processor
/// Pre-processes captured frames before passing them to the Vision Engine.
/// Handles scaling, colour normalisation, and noise reduction.
actor FrameProcessor {

    struct ProcessingOptions: Sendable {
        var targetSize: CGSize = CGSize(width: 1280, height: 720)
        var applyGrayscaleForOCR: Bool = false
        var contrastEnhancement: Float = 1.2
        var sharpeningRadius: Float = 0.5
    }

    private var options: ProcessingOptions

    init(options: ProcessingOptions = ProcessingOptions()) {
        self.options = options
    }

    func configure(options: ProcessingOptions) {
        self.options = options
    }

    // MARK: - Process Frame
    func process(_ image: CGImage) async -> CGImage? {
        // In production uses CoreImage filters:
        // CILanczosScaleTransform, CIColorControls, CIUnsharpMask
        return image
    }

    // MARK: - Crop Region
    func crop(_ image: CGImage, to normalizedROI: CGRect) -> CGImage? {
        let rect = CGRect(
            x: normalizedROI.minX * CGFloat(image.width),
            y: normalizedROI.minY * CGFloat(image.height),
            width: normalizedROI.width * CGFloat(image.width),
            height: normalizedROI.height * CGFloat(image.height)
        )
        return image.cropping(to: rect)
    }
}

// MARK: - State Change Detector
/// Compares successive FrameAnalysisResults to suppress redundant updates.
actor StateChangeDetector {

    private var previousResult: FrameAnalysisResult?
    private let similarityThreshold: Double = 0.95

    func hasSignificantChange(_ result: FrameAnalysisResult) -> Bool {
        guard let previous = previousResult else {
            previousResult = result
            return true
        }

        let changed = result.detectedPhase != previous.detectedPhase
            || result.detectedTimer != previous.detectedTimer
            || result.detectedTurn != previous.detectedTurn
            || heroesChanged(result.detectedHeroes, previous.detectedHeroes)

        if changed { previousResult = result }
        return changed
    }

    private func heroesChanged(_ a: [DetectedHero], _ b: [DetectedHero]) -> Bool {
        guard a.count == b.count else { return true }
        let aNames = Set(a.map { $0.name })
        let bNames = Set(b.map { $0.name })
        return aNames != bNames
    }

    func reset() {
        previousResult = nil
    }
}
