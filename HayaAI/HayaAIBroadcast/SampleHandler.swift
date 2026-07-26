import ReplayKit
import CoreImage
import CoreGraphics

/// Broadcast Upload Extension — receives every video frame from the iOS system
/// screen broadcast and forwards compressed data to the main Haya AI app via
/// a shared App Group container.
///
/// How it works:
///   1. User taps the "Broadcast" button inside Haya AI (or long-presses the
///      Screen Recording button in Control Center and chooses "Haya AI").
///   2. iOS starts this extension in a separate process.
///   3. While the broadcast runs, every video frame arrives in
///      processSampleBuffer(_:with:).  We compress it to JPEG and write it to
///      the shared App Group container so the main app can read it.
///   4. The main app polls / observes the shared file and feeds each frame into
///      the Vision / OCR pipeline.
///
/// App Group ID:  group.com.hayaai.app
///   – Must be registered in both the main app AND this extension target.
///   – For sideloaded apps, ESign/Sideloadly will adjust the ID to match your
///     personal team prefix automatically.
final class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Shared container
    private let appGroupID = "group.com.hayaai.app"
    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    // MARK: - Throttle — write at most 10 fps to save memory/CPU
    private var lastWriteTime: TimeInterval = 0
    private let writeInterval: TimeInterval = 1.0 / 10.0

    // MARK: - Broadcast lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        writeStatus("running")
    }

    override func broadcastPaused() {
        writeStatus("paused")
    }

    override func broadcastResumed() {
        writeStatus("running")
    }

    override func broadcastFinished() {
        writeStatus("stopped")
    }

    // MARK: - Frame delivery

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // Throttle writes
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastWriteTime >= writeInterval else { return }
        lastWriteTime = now

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        writeFrame(imageBuffer)
    }

    // MARK: - Private helpers

    private func writeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let containerURL = sharedContainerURL else { return }

        // Convert to JPEG at reduced quality to keep file size small
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Scale down to 720p to reduce file size while keeping enough detail for OCR
        let scale: CGFloat
        let width = CVPixelBufferGetWidth(pixelBuffer)
        scale = width > 1280 ? 1280.0 / CGFloat(width) : 1.0

        let scaledImage = scale < 1.0
            ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : ciImage

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return }

        let frameURL = containerURL.appendingPathComponent("latest_frame.jpg")
        let timestampURL = containerURL.appendingPathComponent("frame_timestamp.txt")

        if let data = jpegData(from: cgImage, quality: 0.7) {
            try? data.write(to: frameURL, options: .atomic)
            let ts = "\(Date().timeIntervalSinceReferenceDate)"
            try? ts.write(to: timestampURL, atomically: true, encoding: .utf8)
        }
    }

    private func writeStatus(_ status: String) {
        guard let containerURL = sharedContainerURL else { return }
        let statusURL = containerURL.appendingPathComponent("broadcast_status.txt")
        try? status.write(to: statusURL, atomically: true, encoding: .utf8)
    }

    private func jpegData(from cgImage: CGImage, quality: CGFloat) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, "public.jpeg" as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
