import SwiftUI

// MARK: - Live Coach View
/// Full-screen view shown after draft completes. Watches the game
/// and guides the player with real-time alerts, objective timers,
/// kill score, and contextual tactical advice.
struct LiveCoachView: View {
    @EnvironmentObject private var viewModel: LiveCoachViewModel
    @State private var showAlertHistory = false
    @State private var showManualControls = false

    var body: some View {
        ZStack {
            HayaBackground()
            VStack(spacing: 0) {
                topBar
                    .zIndex(10)
                ScrollView {
                    VStack(spacing: 14) {
                        gameStatusRow
                        objectiveTimersRow
                        activeAlertsSection
                        adviceCard
                        minimapWarnings
                        manualControlsSection
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
            }
        }
        .sheet(item: $viewModel.showAlertDetail) { alert in
            AlertDetailSheet(alert: alert)
        }
        .sheet(isPresented: $showAlertHistory) {
            AlertHistorySheet(alerts: viewModel.recentAlertHistory)
        }
        .sheet(isPresented: $showManualControls) {
            ManualControlsSheet()
                .environmentObject(viewModel)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            LiveIndicator(isActive: viewModel.isCapturing)
            Text(viewModel.gameTimeFormatted)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(viewModel.sessionPhase.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(phaseColor(viewModel.sessionPhase).opacity(0.2))
                .foregroundStyle(phaseColor(viewModel.sessionPhase))
                .clipShape(Capsule())
            Spacer()
            Button { showManualControls = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Color.hayaGold)
            }
            Button { showAlertHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Kill Score + Gold Row
    private var gameStatusRow: some View {
        HStack(spacing: 10) {
            KillScoreCard(score: viewModel.killScore)
            Spacer()
            Text(viewModel.killLeadText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(viewModel.killLeadColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(viewModel.killLeadColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Objective Timers
    private var objectiveTimersRow: some View {
        HStack(spacing: 12) {
            ObjectiveTimerCard(
                title: "Turtle",
                icon: "tortoise.fill",
                status: viewModel.turtleStatusText,
                timer: viewModel.turtleTimer,
                urgency: viewModel.turtleUrgency,
                onKilled: { viewModel.manualObjectiveKill(.turtle, team: .friendly) }
            )
            ObjectiveTimerCard(
                title: "Lord",
                icon: "crown.fill",
                status: viewModel.lordStatusText,
                timer: viewModel.lordTimer,
                urgency: viewModel.lordUrgency,
                onKilled: { viewModel.manualObjectiveKill(.lord, team: .friendly) }
            )
        }
    }

    // MARK: - Active Alerts
    private var activeAlertsSection: some View {
        VStack(spacing: 8) {
            if viewModel.activeAlerts.isEmpty {
                GlassCard {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title3)
                        Text("All clear — no critical alerts right now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }
            } else {
                ForEach(viewModel.activeAlerts.prefix(5)) { alert in
                    CoachAlertCard(alert: alert) {
                        viewModel.showAlertDetail = alert
                    } onDismiss: {
                        viewModel.dismissAlert(alert)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.activeAlerts.map { $0.id })
    }

    // MARK: - Advice Card
    private var adviceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Haya's Advice", systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hayaGold)
                Text(viewModel.currentAdvice.isEmpty ? "Analyzing your game..." : viewModel.currentAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut, value: viewModel.currentAdvice)
            }
            .padding(14)
        }
    }

    // MARK: - Minimap Warnings
    @ViewBuilder
    private var minimapWarnings: some View {
        let missing = viewModel.gameState.minimap.missingEnemies
        if !missing.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Enemy MIA", systemImage: "eye.slash.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    HStack(spacing: 6) {
                        ForEach(missing, id: \.self) { name in
                            Text(name)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text("These enemies are off the minimap. Play safe and ward key areas.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
    }

    // MARK: - Manual Controls Section
    private var manualControlsSection: some View {
        EmptyView()
    }
}

// MARK: - Coach Alert Card
struct CoachAlertCard: View {
    let alert: CoachAlert
    let onTap: () -> Void
    let onDismiss: () -> Void
    @State private var offset: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(priorityColor(alert.priority).opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: alert.type.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(priorityColor(alert.priority))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(alert.message)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Spacer()
                            PriorityPill(priority: alert.priority)
                        }
                        if let action = alert.action {
                            Text(action)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(priorityColor(alert.priority))
                        }
                    }
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .offset(x: offset)
        .gesture(
            DragGesture()
                .onChanged { value in offset = value.translation.width }
                .onEnded { value in
                    if value.translation.width < -80 {
                        withAnimation(.spring()) { offset = -500 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                    } else {
                        withAnimation(.spring()) { offset = 0 }
                    }
                }
        )
    }
}

// MARK: - Objective Timer Card
struct ObjectiveTimerCard: View {
    let title: String
    let icon: String
    let status: String
    let timer: ObjectiveTimer
    let urgency: AlertPriority
    let onKilled: () -> Void

    @State private var showKilledConfirm = false

    var body: some View {
        GlassCard {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(urgencyColor)
                        .font(.title3)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if timer.status == .alive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle().stroke(Color.green.opacity(0.4), lineWidth: 4)
                            )
                    }
                }

                // Countdown display
                if let secs = timer.secondsUntilSpawn, secs > 0 {
                    Text(formatSeconds(secs))
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundStyle(urgencyColor)
                        .contentTransition(.numericText())
                        .animation(.spring(), value: secs)
                } else {
                    Text(timer.status == .alive ? "ALIVE" : "—")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(timer.status == .alive ? .green : .secondary)
                }

                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // "We killed it" manual button
                if timer.status == .alive {
                    Button {
                        showKilledConfirm = true
                    } label: {
                        Text("We killed it")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.hayaGold.opacity(0.2))
                            .foregroundStyle(Color.hayaGold)
                            .clipShape(Capsule())
                    }
                    .confirmationDialog("Did your team kill \(title)?", isPresented: $showKilledConfirm) {
                        Button("Yes, we killed \(title)") { onKilled() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .overlay(
            urgency == .critical ? RoundedRectangle(cornerRadius: 16)
                .stroke(urgencyColor.opacity(0.6), lineWidth: 2)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: urgency) : nil
        )
    }

    private var urgencyColor: Color {
        switch urgency {
        case .critical: return .red
        case .high: return .orange
        case .medium: return Color.hayaGold
        case .low: return .secondary
        }
    }

    private func formatSeconds(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return "\(s)s"
    }
}

// MARK: - Kill Score Card
struct KillScoreCard: View {
    let score: KillScore

    var body: some View {
        GlassCard {
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("\(score.friendly)")
                        .font(.title2).fontWeight(.heavy).foregroundStyle(.hayaBlue)
                    Text("Friendly")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Text("vs")
                    .font(.caption2).foregroundStyle(.secondary)
                VStack(spacing: 2) {
                    Text("\(score.enemy)")
                        .font(.title2).fontWeight(.heavy).foregroundStyle(.red)
                    Text("Enemy")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Live Indicator
struct LiveIndicator: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if isActive {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 6)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 2 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulse)
                        .onAppear { pulse = true }
                }
                Circle()
                    .fill(isActive ? Color.red : .secondary)
                    .frame(width: 8, height: 8)
            }
            Text(isActive ? "LIVE" : "IDLE")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(isActive ? .red : .secondary)
        }
    }
}

// MARK: - Priority Pill
struct PriorityPill: View {
    let priority: AlertPriority

    var body: some View {
        Text(priority == .critical ? "!" : priority == .high ? "HIGH" : priority == .medium ? "MED" : "")
            .font(.system(size: 8, weight: .heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.2))
            .foregroundStyle(priorityColor(priority))
            .clipShape(Capsule())
    }
}

// MARK: - Alert Detail Sheet
struct AlertDetailSheet: View {
    let alert: CoachAlert
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(priorityColor(alert.priority).opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: alert.type.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(priorityColor(alert.priority))
                    }
                    Text(alert.message)
                        .font(.title3)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    if let detail = alert.detail {
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    if let action = alert.action {
                        HayaButton(title: action) { dismiss() }
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Dismiss") { dismiss() } } }
        }
    }
}

// MARK: - Alert History Sheet
struct AlertHistorySheet: View {
    let alerts: [CoachAlert]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                if alerts.isEmpty {
                    EmptyStateCard(icon: "clock", title: "No history", message: "Dismissed alerts will appear here.")
                        .padding()
                } else {
                    List(alerts) { alert in
                        HStack(spacing: 10) {
                            Image(systemName: alert.type.icon)
                                .foregroundStyle(priorityColor(alert.priority))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alert.message).font(.subheadline)
                                Text(alert.triggeredAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Alert History")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Manual Controls Sheet
struct ManualControlsSheet: View {
    @EnvironmentObject private var viewModel: LiveCoachViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                List {
                    Section("Game Phase") {
                        ForEach(GameSessionPhase.allCases.filter { $0.isInGame || $0 == .loading }, id: \.self) { phase in
                            Button {
                                viewModel.setPhase(phase)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(phase.rawValue)
                                    Spacer()
                                    if viewModel.sessionPhase == phase {
                                        Image(systemName: "checkmark").foregroundStyle(Color.hayaGold)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                            .listRowBackground(Color.clear)
                        }
                    }
                    Section("Manual Objective Events") {
                        Button("Turtle killed by us") {
                            viewModel.manualObjectiveKill(.turtle, team: .friendly)
                        }
                        .listRowBackground(Color.clear)
                        Button("Turtle killed by enemy") {
                            viewModel.manualObjectiveKill(.turtle, team: .enemy)
                        }
                        .listRowBackground(Color.clear)
                        Button("Lord killed by us") {
                            viewModel.manualObjectiveKill(.lord, team: .friendly)
                        }
                        .listRowBackground(Color.clear)
                        Button("Lord killed by enemy") {
                            viewModel.manualObjectiveKill(.lord, team: .enemy)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Manual Controls")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Helpers
private func priorityColor(_ priority: AlertPriority) -> Color {
    switch priority {
    case .critical: return .red
    case .high: return .orange
    case .medium: return Color.hayaGold
    case .low: return .secondary
    }
}

private func phaseColor(_ phase: GameSessionPhase) -> Color {
    switch phase {
    case .earlyGame: return .orange
    case .midGame: return Color.hayaGold
    case .lateGame: return .red
    case .loading: return .secondary
    case .draft: return Color.hayaBlue
    default: return .secondary
    }
}
