import SwiftUI

// MARK: - Game Mode Container View
/// Top-level container for the Draft → Live Game → Post-Game flow.
/// Automatically transitions between the Draft Assistant and Live Coach
/// based on the GameSessionManager's detected phase.
struct GameModeContainerView: View {
    @EnvironmentObject private var draftViewModel: DraftAssistantViewModel
    @EnvironmentObject private var draftStateManager: DraftStateManager
    @ObservedObject private var liveCoachViewModel: LiveCoachViewModel
    @ObservedObject private var sessionManager: GameSessionManager

    @State private var showLiveCoach: Bool = false
    @State private var showTransitionOverlay: Bool = false

    init(
        liveCoachViewModel: LiveCoachViewModel,
        sessionManager: GameSessionManager
    ) {
        self.liveCoachViewModel = liveCoachViewModel
        self.sessionManager = sessionManager
    }

    var body: some View {
        ZStack {
            // Draft or Live Coach view
            if showLiveCoach {
                LiveCoachView()
                    .environmentObject(liveCoachViewModel)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                DraftAssistantView()
                    .environmentObject(draftViewModel)
                    .environmentObject(draftStateManager)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            // Phase transition overlay (brief)
            if showTransitionOverlay {
                PhaseTransitionOverlay(phase: sessionManager.sessionPhase)
                    .transition(.opacity)
                    .zIndex(100)
            }

            // Floating top alert (shown even on draft screen)
            if !showLiveCoach,
               let topAlert = liveCoachViewModel.topAlert,
               topAlert.priority >= .high {
                VStack {
                    CompactAlertBanner(alert: topAlert) {
                        withAnimation(.spring()) { showLiveCoach = true }
                    } onDismiss: {
                        liveCoachViewModel.dismissTopAlert()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    Spacer()
                }
                .zIndex(50)
            }
        }
        .onChange(of: sessionManager.sessionPhase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showLiveCoach)
    }

    private func handlePhaseChange(_ phase: GameSessionPhase) {
        let shouldShowLive = phase.isInGame

        if shouldShowLive && !showLiveCoach {
            // Show transition overlay briefly
            showTransitionOverlay = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showTransitionOverlay = false
                    showLiveCoach = true
                }
            }
        } else if !shouldShowLive && showLiveCoach {
            withAnimation { showLiveCoach = false }
        }
    }
}

// MARK: - Compact Alert Banner
/// A slim notification banner shown at the top of the draft screen when
/// a high-priority in-game alert fires before the user switches to the live view.
struct CompactAlertBanner: View {
    let alert: CoachAlert
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: alert.type.icon)
                    .font(.subheadline)
                    .foregroundStyle(priorityColorForAlert)
                Text(alert.message)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text("View")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(priorityColorForAlert)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(priorityColorForAlert.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: priorityColorForAlert.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var priorityColorForAlert: Color {
        switch alert.priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return Color.hayaGold
        case .low: return .secondary
        }
    }
}

// MARK: - Phase Transition Overlay
struct PhaseTransitionOverlay: View {
    let phase: GameSessionPhase
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 60))
                    .foregroundStyle(phaseColorForOverlay)
                    .symbolEffect(.pulse)
                Text(phase.rawValue.uppercased())
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(4)
                Text(phaseSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .earlyGame: return "sunrise.fill"
        case .midGame: return "sun.max.fill"
        case .lateGame: return "moon.stars.fill"
        default: return "gamecontroller.fill"
        }
    }

    private var phaseColorForOverlay: Color {
        switch phase {
        case .earlyGame: return .orange
        case .midGame: return Color.hayaGold
        case .lateGame: return Color.hayaBlue
        default: return .white
        }
    }

    private var phaseSubtitle: String {
        switch phase {
        case .earlyGame: return "Haya AI is now coaching you live"
        case .midGame: return "Mid game — contest Turtle and group up"
        case .lateGame: return "Late game — secure Lord and end the match"
        default: return ""
        }
    }
}
