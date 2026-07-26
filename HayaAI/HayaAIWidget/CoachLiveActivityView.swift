import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct CoachLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoachLiveActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: context.state.topAlertIcon)
                            .font(.caption).foregroundColor(.orange)
                        Text(context.state.killScore)
                            .font(.caption).bold().foregroundColor(.yellow)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.objectiveCountdown.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "timer")
                                .font(.caption2).foregroundColor(.orange)
                            Text(context.state.objectiveCountdown)
                                .font(.caption2).bold().foregroundColor(.orange)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.topAlertMessage)
                        .font(.caption).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if !context.attributes.heroName.isEmpty {
                            Text(context.attributes.heroName)
                                .font(.caption2).foregroundColor(.gray)
                        }
                        Spacer()
                        Text("\(context.state.phase) · \(context.state.gameTime)")
                            .font(.caption2).foregroundColor(.gray)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.topAlertIcon)
                    .font(.caption).foregroundColor(.orange)
            } compactTrailing: {
                Text(context.state.gameTime)
                    .font(.caption2).monospacedDigit().foregroundColor(.white)
            } minimal: {
                Image(systemName: context.state.topAlertIcon)
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Lock Screen / Notification View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<CoachLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.topAlertIcon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.topAlertMessage)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !context.attributes.heroName.isEmpty {
                        Text(context.attributes.heroName)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(context.state.phase)
                        .font(.caption2).foregroundStyle(.secondary)
                    if !context.state.objectiveCountdown.isEmpty {
                        Text("·").foregroundStyle(.secondary)
                        Text(context.state.objectiveCountdown)
                            .font(.caption2).bold().foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.killScore)
                    .font(.headline).bold().foregroundStyle(.yellow)
                Text(context.state.gameTime)
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.05, green: 0.05, blue: 0.12))
    }
}
