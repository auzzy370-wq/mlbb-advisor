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
        preferredContentSize = CGSize(width: 220, height: 120)
    }
}

// MARK: - PiP Display State
struct PiPDisplayState {
    var gameTime: String?
    var friendlyKills: Int?
    var enemyKills: Int?
    var heroName: String?
    var phase: String
    var isLiveData: Bool
    var message: String
    var icon: String
    var priority: AlertPriority
    var isCapturing: Bool
    var buildHint: PiPBuildHint?
    var displayMode: PiPDisplayMode

    static var idle: PiPDisplayState {
        PiPDisplayState(
            gameTime: nil, friendlyKills: nil, enemyKills: nil,
            heroName: nil, phase: "Waiting",
            isLiveData: false,
            message: "Start a broadcast to begin coaching",
            icon: "eye.slash",
            priority: .low,
            isCapturing: false,
            buildHint: nil,
            displayMode: .coaching
        )
    }
}

// MARK: - Coach PiP Content View
struct CoachPiPContentView: View {
    var state: PiPDisplayState = .idle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(0.90))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor.opacity(0.7), lineWidth: 1.5)
                )

            VStack(spacing: 0) {
                headerRow
                statsRow
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                contentRow
                footerRow
            }
        }
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(state.isLiveData ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("HAYA AI")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(state.isLiveData ? Color.green : Color.gray)

            Spacer()

            // Mode indicator pill
            modeLabel

            Spacer()

            // Show the live game clock when in a match; show the phase label otherwise.
            if let t = state.gameTime {
                Text(t)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            } else {
                Text(preGameLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.gray.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private var modeLabel: some View {
        Group {
            switch state.displayMode {
            case .coaching:
                Label("TIP", systemImage: "lightbulb.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.yellow.opacity(0.8))
            case .nextBuy:
                Label("BUILD", systemImage: "cart.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.cyan.opacity(0.9))
            case .counterBuild:
                Label("COUNTER", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        if let f = state.friendlyKills, let e = state.enemyKills {
            HStack(spacing: 4) {
                Text("\(f)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(f >= e ? Color.green : Color.red)
                Text(":")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                Text("\(e)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(e > f ? Color.red : Color.white.opacity(0.7))
                Spacer()
                Text(killLeadText(f: f, e: e))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(f > e ? Color.green : f < e ? Color.red : Color.orange)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
        } else if !state.isLiveData {
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
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var contentRow: some View {
        if let hint = state.buildHint, state.displayMode != .coaching {
            buildHintRow(hint)
        } else {
            coachingRow
        }
    }

    private func buildHintRow(_ hint: PiPBuildHint) -> some View {
        HStack(alignment: .top, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(hint.isCounter ? Color.orange.opacity(0.18) : Color.cyan.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: hint.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hint.isCounter ? Color.orange : Color.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(hint.itemName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(hint.reason)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private var coachingRow: some View {
        HStack(alignment: .top, spacing: 6) {
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
    }

    private var footerRow: some View {
        HStack(spacing: 4) {
            if let hero = state.heroName {
                Text(hero)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text("·")
                    .foregroundStyle(.white.opacity(0.2))
            }
            Text(state.phase)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    /// Compact phase label shown in the clock position before the match starts.
    private var preGameLabel: String {
        switch state.phase {
        case "Draft":   return "DRAFT"
        case "Loading": return "LOADING"
        case "Idle":    return "READY"
        default:        return state.phase.uppercased()
        }
    }

    private var borderColor: Color {
        guard state.isLiveData else { return .gray.opacity(0.4) }
        switch state.displayMode {
        case .nextBuy:      return .cyan
        case .counterBuild: return .orange
        case .coaching:
            switch state.priority {
            case .critical: return .red
            case .high:     return .orange
            case .medium:   return Color(red: 1, green: 0.8, blue: 0)
            case .low:      return .green
            }
        }
    }

    private func killLeadText(f: Int, e: Int) -> String {
        let diff = f - e
        if diff > 2  { return "+\(diff) AHEAD" }
        if diff < -2 { return "\(diff) BEHIND" }
        return "EVEN"
    }
}
