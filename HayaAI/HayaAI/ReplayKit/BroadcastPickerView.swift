import SwiftUI
import ReplayKit
import UIKit

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

// MARK: - PiP Launch Button
/// A button that starts the floating Picture-in-Picture coaching window.
/// The user taps this once, then switches to MLBB — the coaching panel
/// will float on top of the game.
struct PiPLaunchButton: UIViewRepresentable {
    @EnvironmentObject private var liveCoachVM: LiveCoachViewModel

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        container.backgroundColor = .clear

        let button = UIButton(type: .system)
        button.frame = container.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        button.tintColor = UIColor.systemYellow
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)), for: .touchUpInside)
        container.addSubview(button)
        context.coordinator.button = button
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let active = liveCoachVM.pipManager.isActive
        context.coordinator.button?.tintColor = active ? .systemGreen : .systemYellow
        context.coordinator.button?.setImage(
            UIImage(systemName: active ? "pip.exit" : "pip.enter"), for: .normal
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: liveCoachVM)
    }

    @MainActor
    class Coordinator: NSObject {
        let vm: LiveCoachViewModel
        weak var button: UIButton?
        weak var container: UIView?

        init(vm: LiveCoachViewModel) { self.vm = vm }

        @objc func tapped(_ sender: UIButton) {
            if vm.pipManager.isActive {
                vm.pipManager.stop()
            } else if let view = container {
                vm.pipManager.start(from: view)
            }
        }
    }
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
