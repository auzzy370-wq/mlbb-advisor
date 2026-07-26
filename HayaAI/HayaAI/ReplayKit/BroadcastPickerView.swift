import SwiftUI
import ReplayKit

/// Wraps RPSystemBroadcastPickerView — when tapped this shows the native iOS
/// "Start Broadcast" sheet that lets the user pick "Haya AI" as the broadcast
/// destination.  Tapping it again stops the broadcast.
struct BroadcastPickerButton: UIViewRepresentable {
    /// Bundle identifier of the Broadcast Upload Extension.
    private let extensionBundleID = "com.hayaai.app.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = extensionBundleID
        picker.showsMicrophoneButton = false
        // Tint the built-in button to match our accent colour
        if let button = picker.subviews.first(where: { $0 is UIButton }) as? UIButton {
            button.tintColor = UIColor(Color.hayaBlue)
            button.imageView?.contentMode = .scaleAspectFit
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

/// Full-width broadcast control card shown on the Draft Assistant screen when
/// the broadcast extension is available.
struct BroadcastControlCard: View {
    let isActive: Bool
    let framesReceived: Int

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                // Status dot
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .overlay(
                        isActive
                            ? Circle().stroke(Color.green.opacity(0.35), lineWidth: 5)
                                .animation(.easeInOut(duration: 1).repeatForever(), value: isActive)
                            : nil
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(isActive ? "Broadcast Active" : "Broadcast Off")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isActive ? .primary : .secondary)
                    Text(isActive
                         ? "Receiving screen · \(framesReceived) frames"
                         : "Tap  ●  to start capturing your screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // The real iOS broadcast picker button
                BroadcastPickerButton()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }
        }
    }
}
