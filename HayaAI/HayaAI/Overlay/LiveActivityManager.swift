import Foundation
import ActivityKit

/// Manages the lifecycle of the Live Activity that displays coaching info
/// on the Dynamic Island and Lock Screen while the user plays Mobile Legends.
@MainActor
final class LiveActivityManager: ObservableObject {

    @Published private(set) var isActive = false

    private var currentActivity: Activity<CoachLiveActivityAttributes>?

    // MARK: - Start

    func start(heroName: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard currentActivity == nil else { return }

        let state = CoachLiveActivityAttributes.ContentState(
            phase: "Starting",
            gameTime: "0:00",
            topAlertMessage: "Haya AI is watching — good luck!",
            topAlertIcon: "eye.fill",
            objectiveCountdown: "",
            killScore: "0-0"
        )
        do {
            currentActivity = try Activity<CoachLiveActivityAttributes>.request(
                attributes: CoachLiveActivityAttributes(heroName: heroName),
                content: ActivityContent(state: state, staleDate: nil)
            )
            isActive = true
        } catch {
            // Live Activities unavailable (e.g. not supported, user disabled) — fail silently
        }
    }

    // MARK: - Update

    func update(gameState: LiveGameState, topAlert: CoachAlert?) async {
        guard let activity = currentActivity else { return }

        let alertMsg: String
        let alertIcon: String
        if let alert = topAlert, alert.isActive {
            alertMsg = alert.message
            alertIcon = alert.type.icon
        } else {
            (alertMsg, alertIcon) = phaseAdvice(for: gameState)
        }

        var countdown = ""
        if let secs = gameState.objectives.lord.secondsUntilSpawn, secs <= 90 {
            countdown = "Lord \(secs)s"
        } else if let secs = gameState.objectives.turtle.secondsUntilSpawn, secs <= 60 {
            countdown = "Turtle \(secs)s"
        }

        let state = CoachLiveActivityAttributes.ContentState(
            phase: gameState.sessionPhase.rawValue,
            gameTime: gameState.gameTimeFormatted,
            topAlertMessage: alertMsg,
            topAlertIcon: alertIcon,
            objectiveCountdown: countdown,
            killScore: "\(gameState.killScore.friendly)-\(gameState.killScore.enemy)"
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    // MARK: - End

    func end() async {
        let endState = CoachLiveActivityAttributes.ContentState(
            phase: "Game Over",
            gameTime: "",
            topAlertMessage: "Game ended — well played!",
            topAlertIcon: "flag.checkered",
            objectiveCountdown: "",
            killScore: ""
        )
        await currentActivity?.end(
            ActivityContent(state: endState, staleDate: nil),
            dismissalPolicy: .default
        )
        currentActivity = nil
        isActive = false
    }

    // MARK: - Helpers

    private func phaseAdvice(for state: LiveGameState) -> (String, String) {
        switch state.sessionPhase {
        case .earlyGame:
            return ("Farm efficiently — build toward your first core item.", "shield.fill")
        case .midGame:
            return ("Group for Turtle fights. Keep wards on key bushes.", "tortoise.fill")
        case .lateGame:
            return ("GROUP UP for Lord. Never split in late game.", "crown.fill")
        case .loading:
            return ("Game loading — review your build.", "hourglass")
        default:
            return ("Haya AI is watching...", "eye.fill")
        }
    }
}
