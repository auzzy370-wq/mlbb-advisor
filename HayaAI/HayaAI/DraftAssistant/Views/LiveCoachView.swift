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
                        inGameRecommendationsPanel
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

    // MARK: - In-Game Recommendations Panel
    @ViewBuilder
    private var inGameRecommendationsPanel: some View {
        if let pkg = viewModel.inGamePackage {
            GlassCard {
                VStack(spacing: 0) {
                    // Header row: "Hero Guidance" + loading indicator
                    HStack {
                        Label(pkg.heroName.isEmpty ? "Hero Guidance" : "\(pkg.heroName) Guidance",
                              systemImage: "star.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.hayaGold)
                        Spacer()
                        if viewModel.isGeneratingRecommendation {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(Color.hayaGold)
                        } else {
                            Text("Updated \(pkg.generatedAt, style: .relative) ago")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // Tab Selector
                    RecommendationTabBar(
                        selectedTab: viewModel.selectedRecommendationTab,
                        onSelect: { viewModel.selectTab($0) }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)

                    // Tab Content
                    Group {
                        switch viewModel.selectedRecommendationTab {
                        case .build:
                            BuildProgressionPanel(progression: pkg.buildProgression)
                        case .targets:
                            TargetPriorityPanel(targets: pkg.targetPriority)
                        case .rotation:
                            RotationPanel(advice: pkg.currentRotation)
                        case .tips:
                            TipsPanel(
                                skillTips: pkg.skillTips,
                                matchupTips: pkg.matchupTips,
                                combo: pkg.comboReminder,
                                powerNote: pkg.powerSpikeNote
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.selectedRecommendationTab)
                }
            }
        } else if viewModel.sessionPhase.isInGame {
            GlassCard {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8).tint(Color.hayaGold)
                    Text("Loading hero guidance…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Manual Controls Section
    private var manualControlsSection: some View {
        EmptyView()
    }
}

// MARK: - Recommendation Tab Bar
struct RecommendationTabBar: View {
    let selectedTab: LiveCoachViewModel.InGameTab
    let onSelect: (LiveCoachViewModel.InGameTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LiveCoachViewModel.InGameTab.allCases, id: \.self) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selectedTab == tab
                            ? Color.hayaGold.opacity(0.18)
                            : Color.clear
                    )
                    .foregroundStyle(selectedTab == tab ? Color.hayaGold : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.25), value: selectedTab)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Build Progression Panel
struct BuildProgressionPanel: View {
    let progression: BuildProgression
    @State private var showAllItems = false

    var body: some View {
        VStack(spacing: 10) {
            // Summary bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build Progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(progression.completedSteps.count) / \(progression.steps.count) items")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Spacer()
                if progression.goldNeededForNext > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.hayaGold)
                        Text("\(progression.goldNeededForNext) more gold")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.hayaGold)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.hayaBlue, Color.hayaGold],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progression.completionPercent, height: 6)
                        .animation(.spring(), value: progression.completionPercent)
                }
            }
            .frame(height: 6)

            // Build note
            if !progression.buildNote.isEmpty {
                Text(progression.buildNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().background(Color.white.opacity(0.1))

            // Next to buy — highlighted
            if let next = progression.nextStep {
                BuildItemRow(step: next, isHighlighted: true)
            }

            // Remaining steps
            let remaining = progression.remainingSteps.dropFirst()
            let shown = showAllItems ? Array(remaining) : Array(remaining.prefix(2))

            ForEach(shown) { step in
                BuildItemRow(step: step, isHighlighted: false)
            }

            if remaining.count > 2 {
                Button {
                    withAnimation { showAllItems.toggle() }
                } label: {
                    Text(showAllItems ? "Show less" : "Show \(remaining.count - 2) more items")
                        .font(.caption)
                        .foregroundStyle(Color.hayaBlue)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            // Completed items footer
            if !progression.completedSteps.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
                    Text("Owned: \(progression.completedSteps.map { $0.item.name }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct BuildItemRow: View {
    let step: BuildStep
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Order badge
            ZStack {
                Circle()
                    .fill(isHighlighted ? Color.hayaGold : Color.white.opacity(0.1))
                    .frame(width: 26, height: 26)
                Text("\(step.order)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(isHighlighted ? .black : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.item.name)
                        .font(.subheadline)
                        .fontWeight(isHighlighted ? .bold : .medium)
                        .foregroundStyle(isHighlighted ? .primary : .secondary)
                    UrgencyBadge(urgency: step.urgency)
                }
                Text(step.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(isHighlighted ? 2 : 1)
            }

            Spacer()

            Text("\(step.costGold)g")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.hayaGold.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.hayaGold.opacity(0.07) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            isHighlighted ? RoundedRectangle(cornerRadius: 8)
                .stroke(Color.hayaGold.opacity(0.3), lineWidth: 1) : nil
        )
    }
}

struct UrgencyBadge: View {
    let urgency: BuildStep.BuildUrgency

    var body: some View {
        if urgency != .core {
            Text(urgency.rawValue)
                .font(.system(size: 8, weight: .heavy))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    private var color: Color {
        switch urgency {
        case .counter: return .red
        case .situational: return .orange
        case .optional: return .secondary
        case .core: return .clear
        }
    }
}

// MARK: - Target Priority Panel
struct TargetPriorityPanel: View {
    let targets: [TargetRecommendation]

    var body: some View {
        VStack(spacing: 8) {
            if targets.isEmpty {
                Text("Enemy picks not detected yet. Targets will appear when the draft is read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(targets.prefix(5)) { target in
                    TargetRow(target: target)
                }
            }
        }
    }
}

struct TargetRow: View {
    let target: TargetRecommendation
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    // Priority number
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(priorityBadgeColor(target.priority).opacity(0.2))
                            .frame(width: 28, height: 28)
                        Text("#\(target.priority.priorityNumber)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(priorityBadgeColor(target.priority))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(target.heroName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(target.heroRole.rawValue)
                                .font(.system(size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(target.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    DangerBadge(level: target.dangerLevel)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ExpandedRow(icon: "bolt.fill", color: .orange, label: "How to kill", text: target.howToKill)
                    if !target.canYouKill {
                        ExpandedRow(icon: "exclamationmark.triangle.fill", color: .red, label: "Caution", text: "Difficult matchup — don't engage 1v1 without help.")
                    }
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(Color.white.opacity(0.06))
        }
    }

    private func priorityBadgeColor(_ p: TargetPriority) -> Color {
        switch p.priorityLevel {
        case .critical: return .red
        case .high: return .orange
        case .medium: return Color.hayaGold
        case .low: return .secondary
        }
    }
}

struct DangerBadge: View {
    let level: TargetRecommendation.DangerLevel

    var body: some View {
        Text(level.rawValue)
            .font(.system(size: 8, weight: .heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch level {
        case .safe: return .green
        case .moderate: return Color.hayaGold
        case .dangerous: return .orange
        case .extreme: return .red
        }
    }
}

struct ExpandedRow: View {
    let icon: String
    let color: Color
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Rotation Panel
struct RotationPanel: View {
    let advice: RotationAdvice

    var body: some View {
        VStack(spacing: 12) {
            // Main destination
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(urgencyColor(advice.urgency).opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: advice.destination.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(urgencyColor(advice.urgency))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.destination.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(advice.urgency.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(urgencyColor(advice.urgency).opacity(0.2))
                        .foregroundStyle(urgencyColor(advice.urgency))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(urgencyColor(advice.urgency).opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Why
            RotationInfoRow(icon: "questionmark.circle.fill", label: "Why", text: advice.reason)

            // Time window
            RotationInfoRow(icon: "timer", label: "When", text: advice.timeWindow)

            // After rotation
            RotationInfoRow(icon: "arrow.right.circle.fill", label: "After", text: advice.afterRotation)

            // If behind
            RotationInfoRow(icon: "exclamationmark.circle.fill", label: "If behind", text: advice.alternativeIfBehind)
        }
    }

    private func urgencyColor(_ urgency: RotationAdvice.RotationUrgency) -> Color {
        switch urgency {
        case .immediate: return .red
        case .soon: return .orange
        case .whenReady: return Color.hayaGold
        case .optional: return .secondary
        }
    }
}

struct RotationInfoRow: View {
    let icon: String
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tips Panel
struct TipsPanel: View {
    let skillTips: [SkillTip]
    let matchupTips: [MatchupTip]
    let combo: ComboReminder?
    let powerNote: String

    var body: some View {
        VStack(spacing: 12) {
            // Power spike
            if !powerNote.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Color.hayaGold)
                        .font(.caption)
                    Text(powerNote)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hayaGold.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Combo reminder
            if let combo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(combo.name)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.hayaBlue)
                        Spacer()
                        Text(combo.context)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        ForEach(combo.steps.indices, id: \.self) { idx in
                            Text(combo.steps[idx])
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.hayaBlue.opacity(0.2))
                                .foregroundStyle(Color.hayaBlue)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            if idx < combo.steps.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(combo.triggerCondition)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.hayaBlue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Skill tips
            if !skillTips.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                Text("Skill Tips")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(skillTips) { tip in
                    SkillTipRow(tip: tip)
                }
            }

            // Matchup tips
            if !matchupTips.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                Text("Matchup Tips")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(matchupTips.prefix(3)) { tip in
                    MatchupTipRow(tip: tip)
                }
            }
        }
    }
}

struct SkillTipRow: View {
    let tip: SkillTip

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tip.useNow ? Color.red.opacity(0.2) : Color.white.opacity(0.07))
                    .frame(width: 36, height: 26)
                Text(tip.skillName)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(tip.useNow ? .red : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if tip.useNow {
                        Text("USE NOW")
                            .font(.system(size: 8, weight: .heavy))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    if let combo = tip.comboHint {
                        Text(combo)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color.hayaBlue)
                    }
                }
                Text(tip.tip)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = tip.cooldownNote {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .italic()
                }
            }

            Spacer()
        }
        .padding(8)
        .background(tip.useNow ? Color.red.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MatchupTipRow: View {
    let tip: MatchupTip
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.viewfinder")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("vs \(tip.enemyHeroName)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ExpandedRow(icon: "checkmark.circle.fill", color: .green, label: "How to win", text: tip.tip)
                    ExpandedRow(icon: "xmark.circle.fill", color: .red, label: "Avoid", text: tip.avoidNote)
                    ExpandedRow(icon: "clock", color: .blue, label: "Fight window", text: tip.windowToFight)
                    if let skillCounter = tip.counterSkill {
                        ExpandedRow(icon: "bolt.circle.fill", color: Color.hayaGold, label: "Counter skill", text: skillCounter)
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
