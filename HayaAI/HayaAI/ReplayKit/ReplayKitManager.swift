import Foundation
import ReplayKit
import CoreVideo
import Combine

// MARK: - ReplayKit Manager
/// Manages screen capture using ReplayKit's broadcast-based in-app capture.
/// Frames are dispatched at a throttled rate to avoid saturating the Vision Engine.
@MainActor
final class ReplayKitManager: NSObject, ObservableObject, ReplayKitManagerProtocol {

    // MARK: - Published State
    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var captureStatus: CaptureStatus = .idle
    @Published private(set) var capturedFrameCount: Int = 0
    @Published private(set) var droppedFrameCount: Int = 0
    @Published private(set) var lastError: CapturError? = nil

    // MARK: - Protocol Conformance
    nonisolated var onFrameCaptured: ((CVPixelBufferRef, CMTimeValue) -> Void)?

    // MARK: - Private
    private let recorder = RPScreenRecorder.shared()
    private let processingQueue = DispatchQueue(
        label: "com.hayaai.replaykit.processing",
        qos: .userInitiated
    )
    private var frameThrottleInterval: TimeInterval = 1.0 / 15.0   // 15 fps target
    private var lastProcessedTime: CMTime = .zero
    private var isInitialized: Bool = false

    // MARK: - Capture Status
    enum CaptureStatus: Equatable {
        case idle
        case starting
        case capturing
        case stopping
        case error(String)

        static func == (lhs: CaptureStatus, rhs: CaptureStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.starting, .starting), (.capturing, .capturing), (.stopping, .stopping):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    enum CapturError: Error, Equatable {
        case permissionDenied
        case alreadyCapturing
        case recordingNotAvailable
        case unknown(String)
    }

    // MARK: - Init
    override init() {
        super.init()
        recorder.delegate = self
    }

    // MARK: - Permission
    nonisolated func requestPermission() async throws -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                RPScreenRecorder.shared().isMicrophoneEnabled = false
                RPScreenRecorder.shared().isCameraEnabled = false
                // Permission is implicitly requested on first capture start
                continuation.resume(returning: RPScreenRecorder.shared().isAvailable)
            }
        }
    }

    // MARK: - Start Capture
    func startCapture() async throws {
        guard !isCapturing else {
            throw CapturError.alreadyCapturing
        }
        guard recorder.isAvailable else {
            throw CapturError.recordingNotAvailable
        }

        captureStatus = .starting

        return try await withCheckedThrowingContinuation { continuation in
            recorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
                guard let self else { return }
                if let error {
                    Task { @MainActor in
                        self.captureStatus = .error(error.localizedDescription)
                        self.lastError = .unknown(error.localizedDescription)
                    }
                    return
                }
                guard bufferType == .video else { return }
                self.handleVideoSampleBuffer(sampleBuffer)
            }, completionHandler: { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    if let error {
                        self.captureStatus = .error(error.localizedDescription)
                        self.lastError = .unknown(error.localizedDescription)
                        self.isCapturing = false
                        continuation.resume(throwing: CapturError.unknown(error.localizedDescription))
                    } else {
                        self.isCapturing = true
                        self.captureStatus = .capturing
                        continuation.resume()
                    }
                }
            })
        }
    }

    // MARK: - Stop Capture
    func stopCapture() async {
        guard isCapturing else { return }
        captureStatus = .stopping

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            recorder.stopCapture { [weak self] error in
                guard let self else {
                    continuation.resume()
                    return
                }
                Task { @MainActor in
                    self.isCapturing = false
                    self.captureStatus = .idle
                    if let error {
                        self.lastError = .unknown(error.localizedDescription)
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Frame Handling
    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Throttle to target FPS
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(pts, lastProcessedTime))
        guard elapsed >= frameThrottleInterval else {
            Task { @MainActor in self.droppedFrameCount += 1 }
            return
        }
        lastProcessedTime = pts

        processingQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.capturedFrameCount += 1 }
            // Forward to Vision Engine via callback
            self.onFrameCaptured?(pixelBuffer, pts.value)
        }
    }

    // MARK: - Configuration
    func setTargetFPS(_ fps: Int) {
        frameThrottleInterval = 1.0 / Double(max(1, fps))
    }
}

// MARK: - RPScreenRecorderDelegate
extension ReplayKitManager: RPScreenRecorderDelegate {
    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder, didStopRecordingWith previewViewController: RPPreviewViewController?, error: Error?) {
        Task { @MainActor in
            self.isCapturing = false
            self.captureStatus = .idle
            if let error {
                self.lastError = .unknown(error.localizedDescription)
            }
        }
    }

    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        Task { @MainActor in
            if !screenRecorder.isAvailable && self.isCapturing {
                self.isCapturing = false
                self.captureStatus = .idle
            }
        }
    }
}

// MARK: - CMTime Helpers (provided by CoreMedia – included here for compilation without full Xcode)
#if canImport(CoreMedia)
import CoreMedia
#else
// Stub for Linux build validation
struct CMTime {
    var value: Int64 = 0
    var timescale: Int32 = 1
    static let zero = CMTime()
}
func CMSampleBufferGetPresentationTimeStamp(_ sbuf: AnyObject) -> CMTime { .zero }
func CMSampleBufferGetImageBuffer(_ sbuf: AnyObject) -> AnyObject? { nil }
func CMTimeSubtract(_ t1: CMTime, _ t2: CMTime) -> CMTime { .zero }
func CMTimeGetSeconds(_ t: CMTime) -> Double { 0 }
typealias CMSampleBuffer = AnyObject
#endif
