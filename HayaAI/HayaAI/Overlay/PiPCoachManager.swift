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

    // Internal game clock — ticks whenever PiP is active so coaching tips
    // fire on schedule even if OCR hasn't detected a game clock yet.
    private var clockTask: Task<Void, Never>?
    private var elapsedSeconds: Int = 0
    private var lastRealGameTime: Int = 0   // last value from OCR/vision
    private var lastExternalAlert: String = ""

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
        startClock()
    }

    /// Updates the floating window with the latest game state from the coach engine.
    func update(alert: CoachAlert?, gameState: LiveGameState) {
        // Sync internal clock to real OCR-detected game time whenever available
        // so the displayed timer matches the actual MLBB clock.
        if gameState.gameTimeSeconds > 0 && abs(gameState.gameTimeSeconds - elapsedSeconds) > 3 {
            elapsedSeconds = gameState.gameTimeSeconds
        }

        guard isActive else { return }

        // Only override the timed tip if there's a real alert
        if let alert = alert, alert.priority >= .medium {
            lastExternalAlert = alert.message
            push(
                message: alert.message,
                icon: alert.type.icon,
                priority: alert.priority,
                gameTime: gameState.gameTimeFormatted,
                phase: gameState.sessionPhase.rawValue
            )
        }
    }

    /// Stops and dismisses the PiP window.
    func stop() {
        clockTask?.cancel()
        clockTask = nil
        elapsedSeconds = 0
        pipController?.stopPictureInPicture()
        pipController = nil
        isActive = false
        deactivateAudioSession()
    }

    // MARK: - Internal clock + timed tips

    private func startClock() {
        clockTask?.cancel()
        elapsedSeconds = 0
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.tick()
            }
        }
    }

    private func tick() {
        elapsedSeconds += 1
        let t = elapsedSeconds
        let (icon, msg, priority) = milestoneTip(at: t)
        let mins = t / 60; let secs = t % 60
        let timeStr = String(format: "%d:%02d", mins, secs)
        push(message: msg, icon: icon, priority: priority, gameTime: timeStr, phase: phaseName(t))
    }

    private func push(message: String, icon: String, priority: AlertPriority,
                      gameTime: String, phase: String) {
        guard isActive else { return }
        contentVC.update(
            message: message,
            icon: icon,
            priority: priority,
            gameTime: gameTime,
            hero: "",
            phase: phase
        )
    }

    private func phaseName(_ t: Int) -> String {
        switch t {
        case 0..<480:  return "Early Game"
        case 480..<900: return "Mid Game"
        default:       return "Late Game"
        }
    }

    /// Returns the most relevant coaching message for a given game time (seconds).
    /// Tips are shown once at milestone times; between milestones the last tip is kept.
    private func milestoneTip(at t: Int) -> (icon: String, message: String, priority: AlertPriority) {
        switch t {
        case 5:
            return ("figure.run", "Farm your lane — don't overextend early", .low)
        case 60:
            return ("eye.fill", "Ward jungle entrance to avoid enemy ganks", .low)
        case 90:
            return ("map.fill", "Check minimap every 5 seconds", .low)
        case 120:
            return ("bolt.fill", "Rotate to assist if ally is getting ganked", .medium)
        case 180:
            return ("star.fill", "Focus on cs — avoid risky fights before 4 min", .low)
        case 210:
            return ("tortoise.fill", "Turtle spawns in 30s — push your lane now", .high)
        case 240:
            return ("exclamationmark.triangle.fill", "Turtle is UP — group up and contest!", .critical)
        case 270:
            return ("arrow.triangle.2.circlepath", "After Turtle — push mid tower together", .high)
        case 330:
            return ("tortoise.fill", "2nd Turtle at ~8 min — set up vision early", .medium)
        case 390:
            return ("crown.fill", "Lord spawns at 8:00 — buy vision ward now", .high)
        case 420:
            return ("exclamationmark.triangle.fill", "Secure Turtle and contest Lord vision", .high)
        case 480:
            return ("crown.fill", "Lord is active — win teamfight to secure!", .critical)
        case 540:
            return ("arrow.right.circle.fill", "Push towers — apply pressure on all lanes", .medium)
        case 600:
            return ("person.3.fill", "Group mid lane — play for teamfights now", .medium)
        case 660:
            return ("tortoise.fill", "3rd Turtle soon — prepare to zone enemy team", .medium)
        case 720:
            return ("house.fill", "Destroy base tower — open the enemy base", .high)
        case 780:
            return ("crown.fill", "Second Lord soon — rotate and vision up", .high)
        case 840:
            return ("flag.checkered", "Late game — one Lord push can end the match", .critical)
        case 900:
            return ("crown.fill", "Lord is CRITICAL — win this fight to close out", .critical)
        default:
            // Between milestones: rotate generic tips every 30s
            let tipIndex = (t / 30) % genericTips.count
            let tip = genericTips[tipIndex]
            return (tip.0, tip.1, .low)
        }
    }

    private let genericTips: [(String, String)] = [
        ("eye.fill",               "Check minimap — track enemy positions"),
        ("heart.fill",             "Recall when below 40% HP — don't feed"),
        ("bolt.fill",              "Use skills aggressively in teamfights"),
        ("arrow.triangle.2.circlepath", "Rotate to help struggling allies"),
        ("dollarsign.circle.fill", "Farm minions between fights for gold"),
        ("shield.fill",            "Stay behind your tank in teamfights"),
        ("map.fill",               "Communicate with your team via pings"),
        ("star.fill",              "Prioritize objectives over kills"),
    ]

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
