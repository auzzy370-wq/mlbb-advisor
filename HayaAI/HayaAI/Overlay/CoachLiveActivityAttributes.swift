import Foundation
import ActivityKit

// Compiled into BOTH the main app target (HayaAI) and the widget extension
// (HayaAIWidget) so both share the exact same struct layout required by
// ActivityKit for matching a live activity to its widget renderer.
struct CoachLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var gameTime: String
        var topAlertMessage: String
        var topAlertIcon: String     // SF Symbol name
        var objectiveCountdown: String   // e.g. "Lord 45s" or ""
        var killScore: String            // e.g. "8-4"
    }
    var heroName: String
}
