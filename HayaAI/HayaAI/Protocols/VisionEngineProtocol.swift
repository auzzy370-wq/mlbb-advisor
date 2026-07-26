import Foundation
import CoreGraphics

// MARK: - Vision Engine Protocol
protocol VisionEngineProtocol: AnyObject, Sendable {
    var isProcessing: Bool { get }
    var onFrameAnalyzed: ((FrameAnalysisResult) -> Void)? { get set }

    func processFrame(_ pixelBuffer: CVPixelBufferRef, timestamp: CMTimeValue) async throws -> FrameAnalysisResult
    func configure(with configuration: VisionEngineConfiguration) async
    func reset() async
}

// Vision Engine Configuration
struct VisionEngineConfiguration: Sendable {
    var targetFPS: Int = 15
    var enableOCR: Bool = true
    var enableHeroDetection: Bool = true
    var enableTimerDetection: Bool = true
    var enablePhaseDetection: Bool = true
    var minimumConfidence: Double = 0.6
    var regionsOfInterest: [VisionROI] = VisionROI.standardROIs
    var deduplicationWindow: TimeInterval = 0.5
}

// CVPixelBufferRef placeholder
typealias CVPixelBufferRef = AnyObject
