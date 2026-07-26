import Foundation
import Vision
import CoreGraphics

// MARK: - Hero Portrait Detector
/// Uses CoreML image classification to identify hero portraits in cropped regions.
/// Falls back to template-matching if the ML model is unavailable.
actor HeroPortraitDetector {

    private var classificationModel: VNCoreMLModel?
    private let fallbackOCR: OCREngine
    private var heroNames: [String] = []

    init() {
        fallbackOCR = OCREngine(heroNames: [])
        Task { await loadModel() }
    }

    // MARK: - Model Loading
    private func loadModel() {
        // In production: load compiled .mlmodel from the app bundle
        // guard let modelURL = Bundle.main.url(forResource: "HeroClassifier", withExtension: "mlmodelc"),
        //       let mlModel = try? MLModel(contentsOf: modelURL),
        //       let vnModel = try? VNCoreMLModel(for: mlModel) else { return }
        // classificationModel = vnModel
    }

    func updateHeroNames(_ names: [String]) async {
        heroNames = names
        await fallbackOCR.updateHeroNames(names)
    }

    // MARK: - Detect Heroes
    func detectHeroes(in image: CGImage, team: DraftTurn) async throws -> [DetectedHero] {
        if let model = classificationModel {
            return try await classifyWithModel(image: image, model: model, team: team)
        }
        return try await detectWithOCR(image: image, team: team)
    }

    // MARK: - ML Classification
    private func classifyWithModel(image: CGImage, model: VNCoreMLModel, team: DraftTurn) async throws -> [DetectedHero] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.5 }
                    .enumerated()
                    .map { index, obs in
                        DetectedHero(
                            name: obs.identifier,
                            boundingBox: CGRect(x: 0, y: CGFloat(index) * 0.2, width: 1, height: 0.2),
                            confidence: Double(obs.confidence),
                            team: team,
                            slotIndex: index,
                            detectionMethod: .imageClassification
                        )
                    }
                continuation.resume(returning: results)
            }
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do { try handler.perform([request]) } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - OCR Fallback
    private func detectWithOCR(image: CGImage, team: DraftTurn) async throws -> [DetectedHero] {
        let texts = try await fallbackOCR.recognizeText(in: image, roi: nil)
        let heroTexts = texts.filter { $0.category == .heroName && $0.confidence > 0.6 }

        return heroTexts.enumerated().map { index, text in
            DetectedHero(
                name: text.text,
                boundingBox: text.boundingBox,
                confidence: text.confidence,
                team: team,
                slotIndex: index,
                detectionMethod: .ocr
            )
        }
    }
}

// MARK: - Phase Detector
actor PhaseDetector {
    /// Detects draft phase by analyzing visual indicators (colour regions / icons)
    /// without relying solely on OCR. A CoreML scene classifier can be added here.
    func detect(in image: CGImage) async throws -> DraftPhase? {
        // TODO: Load and run scene-classification CoreML model for phase detection
        return nil
    }
}

// MARK: - Timer Detector
actor TimerDetector {
    /// Isolates the timer region and uses digit-recognition to extract the countdown value.
    func detect(in image: CGImage) async throws -> Int? {
        // TODO: Run digit-recognition request on the timer ROI
        return nil
    }
}
