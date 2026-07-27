import AVKit
import SwiftUI
import UIKit

// MARK: - Coach PiP View Controller
final class CoachPiPViewController: AVPictureInPictureVideoCallViewController {

    private var hostingVC: UIHostingController<CoachPiPContentView>?

    func update(state: PiPDisplayState) {
        if let hosting = hostingVC {
            hosting.rootView = CoachPiPContentView(state: state)
        } else {
            let hvc = UIHostingController(rootView: CoachPiPContentView(state: state))
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
        preferredContentSize = CGSize(width: 200, height: 110)
    }
}

// MARK: - PiP Display State
/// All data the PiP window needs to render — populated from real OCR detections
/// when available, with clearly-labelled fallbacks when data is absent.
struct PiPDisplayState {
    // Live data — nil means "not yet detected from screen"
    var gameTime: String?           // e.g. "08:32"
    var friendlyKills: Int?
    var enemyKills: Int?
    var heroName: String?           // player's locked hero
    var phase: String               // "Early Game" / "Mid Game" / "Late Game"
    var isLiveData: Bool            // true when real OCR data has arrived recently

    // Coaching message
    var message: String
    var icon: String
    var priority: AlertPriority

    // Broadcast status
    var isCapturing: Bool

    static var idle: PiPDisplayState {
        PiPDisplayState(
            gameTime: nil, friendlyKills: nil, enemyKills: nil,
            heroName: nil, phase: "Waiting",
            isLiveData: false,
            message: "Start a broadcast to begin coaching",
            icon: "eye.slash",
            priority: .low,
            isCapturing: false
        )
    }
}

// MARK: - Coach PiP Content View
struct CoachPiPContentView: View {
    var state: PiPDisplayState = .idle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
                )

            VStack(spacing: 0) {
                // ── Header row ───────────────────────────────────
                HStack(spacing: 6) {
                    // Live indicator dot
                    Circle()
                        .fill(state.isLiveData ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Text("HAYA AI")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(state.isLiveData ? Color.green : Color.gray)

                    Spacer()

                    // Game clock — shows "--:--" until OCR detects it
                    Text(state.gameTime ?? "--:--")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(state.gameTime != nil ? .white : Color.gray.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)

                // ── Score row (only when live data exists) ────────
                if let f = state.friendlyKills, let e = state.enemyKills {
                    HStack(spacing: 4) {
                        Text("\(f)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(f >= e ? Color.green : Color.red)
                        Text(":")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(e)")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(e > f ? Color.red : Color.white.opacity(0.7))

                        Spacer()

                        Text(killLeadText(f: f, e: e))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(f > e ? Color.green : f < e ? Color.red : Color.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                } else if !state.isLiveData {
                    // No data yet — show scanning indicator
                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                        Text("Reading screen...")
                            .font(.system(size: 9))
                            .foregroundStyle(.gray)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 3)
                }

                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                // ── Coaching message ─────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: state.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(borderColor)
                        .frame(width: 14)
                    Text(state.message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)

                // ── Footer: hero + phase ─────────────────────────
                HStack(spacing: 4) {
                    if let hero = state.heroName {
                        Text(hero)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("·")
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    Text(state.phase)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 3)
                .padding(.bottom, 8)
            }
        }
    }

    private var borderColor: Color {
        guard state.isLiveData else { return .gray.opacity(0.4) }
        switch state.priority {
        case .critical: return .red
        case .high:     return .orange
        case .medium:   return Color(red: 1, green: 0.8, blue: 0)
        case .low:      return .green
        }
    }

    private func killLeadText(f: Int, e: Int) -> String {
        let diff = f - e
        if diff > 2  { return "+\(diff) AHEAD" }
        if diff < -2 { return "\(diff) BEHIND" }
        return "EVEN"
    }
}
