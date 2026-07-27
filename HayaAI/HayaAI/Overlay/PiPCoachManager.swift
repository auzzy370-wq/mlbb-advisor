import AVKit
import AVFoundation
import UIKit
import Combine

// MARK: - PiP Coach Manager
/// Manages the floating Picture-in-Picture coaching window.
///
/// The PiP window uses AVPictureInPictureVideoCallViewController so iOS
/// treats it as a persistent call-style window that floats over all apps,
/// including Mobile Legends. The user can reposition it by dragging.
///
/// Usage:
///   1. Call `start(from:)` once when the coaching session begins.
///   2. Call `update(alert:gameState:)` as game state changes.
///   3. Call `stop()` when the session ends.
@MainActor
final class PiPCoachManager: NSObject, ObservableObject {

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isAvailable: Bool = false

    private var pipController: AVPictureInPictureController?
    private let contentVC = CoachPiPViewController()
    private var sourceView: UIView?

    override init() {
        super.init()
        isAvailable = AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - Public API

    /// Starts the PiP window. `sourceView` is any view currently on screen
    /// in the Haya AI app — it anchors the PiP position on launch.
    func start(from sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard !isActive else { return }

        // Activate audio session so iOS allows PiP to persist in background.
        // We use ambient mode so it doesn't interrupt MLBB audio.
        activateAudioSession()

        self.sourceView = sourceView

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = pip

        // Set initial content
        contentVC.update(
            message: "Haya AI is watching",
            icon: "eye.fill",
            priority: .low,
            gameTime: "0:00",
            hero: "",
            phase: "Draft"
        )

        pip.startPictureInPicture()
    }

    /// Updates the floating window with the latest game state.
    func update(alert: CoachAlert?, gameState: LiveGameState) {
        guard isActive else { return }

        let message  = alert?.message ?? gameState.currentAdviceText
        let icon     = alert?.type.icon ?? "lightbulb.fill"
        let priority = alert?.priority ?? .low
        let phase    = gameState.sessionPhase.rawValue

        contentVC.update(
            message: message.isEmpty ? "Stay focused" : message,
            icon: icon,
            priority: priority,
            gameTime: gameState.gameTimeFormatted,
            hero: "",
            phase: phase
        )
    }

    /// Stops and dismisses the PiP window.
    func stop() {
        pipController?.stopPictureInPicture()
        pipController = nil
        isActive = false
        deactivateAudioSession()
    }

    // MARK: - Audio Session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension PiPCoachManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isActive = false }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isActive = false
            print("[PiP] Failed to start: \(error.localizedDescription)")
        }
    }
}

// MARK: - LiveGameState convenience extension
private extension LiveGameState {
    /// Fallback one-line advice text for the PiP idle state.
    var currentAdviceText: String {
        currentAdvice.isEmpty ? phaseIdleText : currentAdvice
    }

    private var phaseIdleText: String {
        switch sessionPhase {
        case .earlyGame: return "Farm efficiently — contest Turtle at 4 min"
        case .midGame:   return "Group up — Turtle and objectives matter now"
        case .lateGame:  return "Push with Lord — one wipe ends the game"
        default:         return "Haya AI is coaching you"
        }
    }
}
