import Foundation
import CoreGraphics
import ImageIO
import Combine

/// Reads compressed frames written by the HayaAIBroadcast extension into the
/// shared App Group container and publishes them to the main app.
///
/// The extension writes `latest_frame.jpg` + `frame_timestamp.txt` at up to
/// 10 fps. This reader polls at the same rate and fires the `onFrame` callback
/// whenever a new frame arrives (identified by timestamp change).
@MainActor
final class BroadcastFrameReader: ObservableObject {

    // MARK: - Public state
    @Published private(set) var isRunning: Bool = false
    /// "running" while the iOS broadcast is active; any other value means idle.
    @Published private(set) var broadcastStatus: String = "stopped"
    @Published private(set) var framesReceived: Int = 0
    /// Convenience flag: true whenever broadcastStatus == "running".
    var isLive: Bool { broadcastStatus == "running" }

    /// Called on the main actor whenever a new frame arrives.
    var onFrame: ((CGImage, TimeInterval) -> Void)?

    // MARK: - Private
    private let appGroupID = "group.com.hayaai.app"
    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private var pollTask: Task<Void, Never>?
    private var lastTimestamp: String = ""

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms = 10 fps
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isRunning = false
    }

    // MARK: - Private

    private func poll() async {
        guard let containerURL else { return }

        // Check broadcast status
        let statusURL = containerURL.appendingPathComponent("broadcast_status.txt")
        if let status = try? String(contentsOf: statusURL, encoding: .utf8) {
            broadcastStatus = status
        }

        // Check for new frame
        let timestampURL = containerURL.appendingPathComponent("frame_timestamp.txt")
        guard let tsString = try? String(contentsOf: timestampURL, encoding: .utf8),
              tsString != lastTimestamp else { return }
        lastTimestamp = tsString

        // Load frame
        let frameURL = containerURL.appendingPathComponent("latest_frame.jpg")
        guard let data = try? Data(contentsOf: frameURL),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }

        framesReceived += 1
        let ts = TimeInterval(tsString) ?? Date().timeIntervalSinceReferenceDate
        onFrame?(cgImage, ts)
    }
}
