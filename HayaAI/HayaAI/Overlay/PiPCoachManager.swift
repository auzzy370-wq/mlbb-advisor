import AVKit
import AVFoundation
import UIKit
import Combine

// MARK: - PiP Coach Manager
/// Manages the floating Picture-in-Picture coaching window.
///
/// Display priority:
///   1. Real alert from coaching engine (priority ≥ medium) — shown immediately
///   2. Real game state (clock/score detected by OCR) — shown between alerts
///   3. Timed fallback tip — only shown if no real screen data in 10+ seconds
@MainActor
final class PiPCoachManager: NSObject, ObservableObject {

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isAvailable: Bool = false

    private var pipController: AVPictureInPictureController?
    private let contentVC = CoachPiPViewController()

    // ── Real data from OCR ──────────────────────────────────────
    private var lastRealDataAt: Date = .distantPast
    private var latestGameTime: String?
    private var latestFriendlyKills: Int?
    private var latestEnemyKills: Int?
    private var latestHero: String?
    private var latestPhase: String = "Waiting"
    private var isCapturing: Bool = false

    // ── Clock ticker ────────────────────────────────────────────
    private var clockTask: Task<Void, Never>?
    private var elapsedSeconds: Int = 0
    private var lastAlertAt: Date = .distantPast
    private var currentAlert: (message: String, icon: String, priority: AlertPriority)?

    override init() {
        super.init()
        isAvailable = AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - Public API

    func start(from sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard !isActive else { return }
        activateAudioSession()

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = pip
        pip.startPictureInPicture()
        startClock()
        push()
    }

    /// Called every time the coaching engine produces a new game state.
    /// Real data from OCR always takes priority over timed tips.
    func update(alert: CoachAlert?, gameState: LiveGameState) {
        // Sync real clock from OCR
        if gameState.gameTimeSeconds > 0 {
            let mins = gameState.gameTimeSeconds / 60
            let secs = gameState.gameTimeSeconds % 60
            latestGameTime = String(format: "%d:%02d", mins, secs)
            if abs(gameState.gameTimeSeconds - elapsedSeconds) > 3 {
                elapsedSeconds = gameState.gameTimeSeconds
            }
            lastRealDataAt = Date()
        }

        // Sync kills
        if gameState.killScore.friendly > 0 || gameState.killScore.enemy > 0 {
            latestFriendlyKills = gameState.killScore.friendly
            latestEnemyKills = gameState.killScore.enemy
            lastRealDataAt = Date()
        }

        latestPhase = gameState.sessionPhase.rawValue
        isCapturing = gameState.sessionPhase != .idle

        // Real coaching alert overrides everything
        if let alert = alert, alert.priority >= .medium {
            currentAlert = (alert.message, alert.type.icon, alert.priority)
            lastAlertAt = Date()
            push()
        }
    }

    /// Called when a hero is locked from draft OCR so PiP shows your hero.
    func setHero(_ heroName: String) {
        latestHero = heroName
        push()
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        isActive = false
        deactivateAudioSession()
    }

    // MARK: - Clock

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.tick()
            }
        }
    }

    private func tick() {
        elapsedSeconds += 1
        // Clear stale alerts (> 8s old)
        if let _ = currentAlert, Date().timeIntervalSince(lastAlertAt) > 8 {
            currentAlert = nil
        }
        push()
    }

    // MARK: - Display

    private func push() {
        guard isActive else { return }

        let hasRealData = Date().timeIntervalSince(lastRealDataAt) < 10

        let (message, icon, priority) = resolveMessage(hasRealData: hasRealData)

        let state = PiPDisplayState(
            gameTime: latestGameTime ?? (elapsedSeconds > 0 ? formattedElapsed() : nil),
            friendlyKills: latestFriendlyKills,
            enemyKills: latestEnemyKills,
            heroName: latestHero,
            phase: latestPhase,
            isLiveData: hasRealData,
            message: message,
            icon: icon,
            priority: priority,
            isCapturing: isCapturing
        )
        contentVC.update(state: state)
    }

    private func resolveMessage(hasRealData: Bool) -> (String, String, AlertPriority) {
        // 1. Active real alert
        if let alert = currentAlert {
            return (alert.message, alert.icon, alert.priority)
        }

        // 2. Real data flowing — generate context-aware tip from actual game state
        if hasRealData {
            return realDataTip()
        }

        // 3. No real data — show fallback timed tip but label it as generic
        return timedFallbackTip()
    }

    private func realDataTip() -> (String, String, AlertPriority) {
        let t = elapsedSeconds
        let f = latestFriendlyKills ?? 0
        let e = latestEnemyKills ?? 0

        // Kill-based tips
        if f - e >= 3 { return ("You're ahead — push towers and take objectives", "bolt.fill", .medium) }
        if e - f >= 3 { return ("You're behind — play safe and farm to scale", "shield.fill", .medium) }
        if e - f >= 5 { return ("Big deficit — group up, avoid solo fights", "exclamationmark.triangle.fill", .high) }

        // Time-based tips using REAL detected clock
        switch t {
        case 210..<250: return ("Turtle spawning soon — push and rotate", "tortoise.fill", .high)
        case 250..<300: return ("Turtle is UP — contest it now!", "exclamationmark.triangle.fill", .critical)
        case 390..<430: return ("Lord spawns at 8:00 — set up vision", "crown.fill", .high)
        case 430..<500: return ("Lord is active — win teamfight to secure!", "crown.fill", .critical)
        case 600..<660: return ("Group mid — rotate for objectives", "person.3.fill", .medium)
        default:
            // Phase-based generic real advice
            switch latestPhase {
            case "Early Game": return ("Track minimap — monitor enemy jungler", "map.fill", .low)
            case "Mid Game":   return ("Group for objectives — don't split", "figure.walk", .low)
            case "Late Game":  return ("One teamfight can end the game — stay together", "flag.checkered", .medium)
            default:           return ("Watching your game...", "eye.fill", .low)
            }
        }
    }

    private func timedFallbackTip() -> (String, String, AlertPriority) {
        switch elapsedSeconds {
        case 0..<5:   return ("Start broadcast to get live coaching", "dot.radiowaves.left.and.right", .low)
        case 5..<30:  return ("Haya AI is scanning the screen...", "viewfinder", .low)
        default:
            // Generic tips — rotate every 20s
            let tips: [(String, String)] = [
                ("Check minimap every few seconds", "map.fill"),
                ("Ward jungle entrances to avoid ganks", "eye.fill"),
                ("Farm between fights for gold advantage", "dollarsign.circle.fill"),
                ("Focus objectives over kills", "star.fill"),
                ("Stay behind your tank in teamfights", "shield.fill"),
                ("Use pings to communicate with team", "bubble.left.fill"),
            ]
            let idx = (elapsedSeconds / 20) % tips.count
            return (tips[idx].0, tips[idx].1, .low)
        }
    }

    private func formattedElapsed() -> String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    // MARK: - Audio Session

    private func activateAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension PiPCoachManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ c: AVPictureInPictureController
    ) { Task { @MainActor in self.isActive = true; self.push() } }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ c: AVPictureInPictureController
    ) { Task { @MainActor in self.isActive = false } }

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) { Task { @MainActor in
        self.isActive = false
        print("[PiP] Failed: \(error.localizedDescription)")
    } }
}
