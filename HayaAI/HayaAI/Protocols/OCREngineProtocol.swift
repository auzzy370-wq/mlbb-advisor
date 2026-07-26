import Foundation
import CoreGraphics

// MARK: - OCR Engine Protocol
protocol OCREngineProtocol: AnyObject, Sendable {
    func recognizeText(in image: CGImage, roi: CGRect?) async throws -> [DetectedText]
    func recognizeHeroName(in image: CGImage, roi: CGRect) async throws -> String?
    func recognizeTimer(in image: CGImage, roi: CGRect) async throws -> Int?
    func recognizePhase(in image: CGImage, roi: CGRect) async throws -> DraftPhase?
}
