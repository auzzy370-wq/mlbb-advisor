import AVKit
import SwiftUI
import UIKit

// MARK: - Coach PiP View Controller
/// A Picture-in-Picture window that floats over Mobile Legends while the user
/// is playing. Implemented as an AVPictureInPictureVideoCallViewController so
/// iOS treats it as a persistent floating window (the same mechanism FaceTime
/// and other video-call apps use).
///
/// The window shows the current top coaching alert and game context. It can
/// be repositioned by the user and survives app switches.
final class CoachPiPViewController: AVPictureInPictureVideoCallViewController {

    // MARK: - Content
    private var hostingVC: UIHostingController<CoachPiPContentView>?

    /// Update is called from LiveCoachViewModel whenever a new alert fires.
    func update(message: String, icon: String, priority: AlertPriority,
                gameTime: String, hero: String, phase: String) {
        let content = CoachPiPContentView(
            message: message,
            icon: icon,
            priority: priority,
            gameTime: gameTime,
            hero: hero,
            phase: phase
        )
        if let hosting = hostingVC {
            hosting.rootView = content
        } else {
            let hvc = UIHostingController(rootView: content)
            hvc.view.backgroundColor = .clear
            addChild(hvc)
            hvc.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(hvc.view)
            NSLayoutConstraint.activate([
                hvc.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                hvc.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                hvc.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hvc.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            ])
            hvc.didMove(toParent: self)
            hostingVC = hvc
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        preferredContentSize = CGSize(width: 160, height: 90)
    }
}

// MARK: - Coach PiP Content View
/// The actual SwiftUI content rendered inside the PiP window.
struct CoachPiPContentView: View {
    var message: String = "Haya AI ready"
    var icon: String = "gamecontroller.fill"
    var priority: AlertPriority = .low
    var gameTime: String = "0:00"
    var hero: String = ""
    var phase: String = "Draft"

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(priorityColor.opacity(0.7), lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Header row
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(priorityColor)
                    Text("HAYA AI")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(priorityColor)
                    Spacer()
                    Text(gameTime)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Message
                Text(message)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Footer
                if !hero.isEmpty {
                    HStack(spacing: 4) {
                        Text(hero)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.3))
                        Text(phase)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var priorityColor: Color {
        switch priority {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return Color(red: 1, green: 0.8, blue: 0)
        case .low:      return .white
        }
    }
}
