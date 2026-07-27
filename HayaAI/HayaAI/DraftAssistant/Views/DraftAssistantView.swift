import SwiftUI

struct DraftAssistantView: View {
    @EnvironmentObject private var viewModel: DraftAssistantViewModel
    @EnvironmentObject private var draftStateManager: DraftStateManager
    @EnvironmentObject private var heroDatabaseService: HeroDatabaseService

    /// Which draft slot is currently awaiting a hero selection.
    @State private var pickerTarget: DraftSlotTarget? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                VStack(spacing: 0) {
                    captureControlBar
                    draftBoardSection
                    tabSelector
                    tabContent
                }
            }
            .navigationTitle("Draft Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .sheet(item: $viewModel.selectedRecommendation) { rec in
            RecommendationDetailSheet(recommendation: rec)
        }
        // Hero picker sheet — opened by tapping any draft slot
        .sheet(item: $pickerTarget) { target in
            HeroPickerSheet(
                target: target,
                heroDatabase: heroDatabaseService
            ) { heroName in
                if target.kind == .ban {
                    viewModel.banHero(heroName, team: target.team, slot: target.slot)
                } else {
                    viewModel.pickHero(heroName, team: target.team, slot: target.slot)
                }
            } onClear: {
                viewModel.clearSlot(team: target.team, slot: target.slot,
                                    isBan: target.kind == .ban)
            }
        }
    }

    // MARK: - Capture Control Bar
    private var captureControlBar: some View {
        let isLive = viewModel.broadcastFrameReader.broadcastStatus == "running"
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Pulsing live indicator
                ZStack {
                    if isLive {
                        Circle().fill(Color.green.opacity(0.3)).frame(width: 16, height: 16)
                    }
                    Circle()
                        .fill(isLive ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isLive ? "Coaching Active" : "Ready to Coach")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(isLive ? .green : .primary)
                    Text(isLive
                         ? "Floating panel + Dynamic Island active"
                         : "Tap ▶ to float panel over MLBB, then broadcast")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // ── Float-over-game PiP button ───────────────────
                PiPLaunchButton()
                    .frame(width: 44, height: 44)

                // ── Broadcast picker ─────────────────────────────
                BroadcastPickerButton()
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isLive
                ? Color.green.opacity(0.08).background(.ultraThinMaterial)
                : Color.clear.background(.ultraThinMaterial))
            .animation(.easeInOut(duration: 0.3), value: isLive)

            if case .error(let msg) = viewModel.captureStatus {
                Text("⚠️ \(msg)")
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
        }
    }

    // MARK: - Draft Board
    private var draftBoardSection: some View {
        DraftBoardView(draftState: viewModel.draftState, pickerTarget: $pickerTarget)
            .padding(.vertical, 8)
    }

    // MARK: - Tab Selector
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(DraftAssistantViewModel.DraftTab.allCases, id: \.self) { tab in
                    TabSelectorButton(
                        title: tab.rawValue.capitalized,
                        isSelected: viewModel.selectedTab == tab
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            // viewModel.selectedTab = tab // would need setter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch viewModel.selectedTab {
                case .recommendations:
                    RecommendationsPanel(
                        recommendations: viewModel.recommendations,
                        isLoading: viewModel.isProcessing,
                        onSelect: { viewModel.selectedRecommendation = $0 }
                    )
                case .teamAnalysis:
                    TeamAnalysisPanel(analysis: viewModel.teamAnalysis)
                case .strategy:
                    StrategyPanel(strategy: viewModel.strategy)
                case .manual:
                    ManualDraftPanel()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await viewModel.resetDraft() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(Color.hayaGold)
            }
        }
    }
}

// MARK: - Draft Board
struct DraftBoardView: View {
    let draftState: DraftState
    @Binding var pickerTarget: DraftSlotTarget?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Friendly side
            VStack(spacing: 6) {
                teamBans(bans: draftState.friendlyBans, team: .friendly)
                teamPicks(picks: draftState.friendlyPicks, team: .friendly)
            }
            .frame(maxWidth: .infinity)

            // Center – phase indicator
            VStack(spacing: 4) {
                PhaseIndicatorBadge(phase: draftState.phase)
                TimerDisplay(seconds: draftState.timer, isActive: draftState.isMyTurn)
                Text("Tap slot\nto pick")
                    .font(.system(size: 8))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 70)

            // Enemy side
            VStack(spacing: 6) {
                teamBans(bans: draftState.enemyBans, team: .enemy)
                teamPicks(picks: draftState.enemyPicks, team: .enemy)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
    }

    private func teamBans(bans: [DraftSlot], team: DraftTurn) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(bans.enumerated()), id: \.element.id) { idx, slot in
                BanSlotView(slot: slot)
                    .onTapGesture {
                        pickerTarget = DraftSlotTarget(team: team, slot: idx, kind: .ban)
                    }
            }
        }
    }

    private func teamPicks(picks: [DraftSlot], team: DraftTurn) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(picks.enumerated()), id: \.element.id) { idx, slot in
                PickSlotView(slot: slot, isAlly: team == .friendly)
                    .onTapGesture {
                        pickerTarget = DraftSlotTarget(team: team, slot: idx, kind: .pick)
                    }
            }
        }
    }
}

// MARK: - Ban Slot
struct BanSlotView: View {
    let slot: DraftSlot

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(slot.heroName != nil ? Color.red.opacity(0.3) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
                .frame(width: 32, height: 32)

            if let name = slot.heroName {
                Text(String(name.prefix(2)))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pick Slot
struct PickSlotView: View {
    let slot: DraftSlot
    let isAlly: Bool

    var body: some View {
        HStack(spacing: 8) {
            if !isAlly { Spacer() }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(heroBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(heroBorder, lineWidth: 1.5)
                    )
                    .frame(width: 40, height: 40)

                heroContent
            }

            if let name = slot.heroName {
                Text(name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Text("Empty")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if isAlly { Spacer() }
        }
    }

    private var heroBackground: Color {
        if slot.heroName != nil {
            return isAlly ? Color.hayaBlue.opacity(0.2) : Color.red.opacity(0.2)
        }
        return Color.white.opacity(0.05)
    }

    private var heroBorder: Color {
        if slot.heroName != nil {
            return isAlly ? Color.hayaBlue.opacity(0.5) : Color.red.opacity(0.5)
        }
        return Color.white.opacity(0.1)
    }

    @ViewBuilder
    private var heroContent: some View {
        if let name = slot.heroName {
            Text(String(name.prefix(2)))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isAlly ? Color.hayaBlue : .red)
        } else {
            Image(systemName: "person")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Phase Indicator Badge
struct PhaseIndicatorBadge: View {
    let phase: DraftPhase

    var body: some View {
        Text(phaseShortLabel)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.2))
            .foregroundStyle(phaseColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(phaseColor.opacity(0.5), lineWidth: 1))
    }

    private var phaseShortLabel: String {
        switch phase {
        case .notStarted: return "READY"
        case .banPhase1, .banPhase2: return "BAN"
        case .pickPhase1, .pickPhase2: return "PICK"
        case .completed: return "DONE"
        case .unknown: return "—"
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .banPhase1, .banPhase2: return .red
        case .pickPhase1, .pickPhase2: return .hayaBlue
        case .completed: return .green
        default: return .secondary
        }
    }
}

// MARK: - Timer Display
struct TimerDisplay: View {
    let seconds: Int
    let isActive: Bool

    var body: some View {
        Text("\(seconds)")
            .font(.system(size: 22, weight: .heavy, design: .monospaced))
            .foregroundStyle(timerColor)
            .contentTransition(.numericText())
            .animation(.spring(), value: seconds)
    }

    private var timerColor: Color {
        if seconds > 15 { return .white }
        if seconds > 8 { return .orange }
        return .red
    }
}

// MARK: - Capture Status Indicator
struct CaptureStatusIndicator: View {
    let status: ReplayKitManager.CaptureStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    statusColor == .green ? Circle().stroke(Color.green.opacity(0.4), lineWidth: 4) : nil
                )
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Not capturing"
        case .starting: return "Starting..."
        case .capturing: return "Live"
        case .stopping: return "Stopping..."
        case .error(let msg): return "Error"
        }
    }

    private var statusColor: Color {
        switch status {
        case .capturing: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .idle: return .secondary
        }
    }
}

// MARK: - Recommendations Panel
struct RecommendationsPanel: View {
    let recommendations: [HeroRecommendation]
    let isLoading: Bool
    let onSelect: (HeroRecommendation) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                LoadingCard(message: "Analyzing draft...")
            } else if recommendations.isEmpty {
                EmptyStateCard(
                    icon: "shield.lefthalf.filled",
                    title: "No Recommendations",
                    message: "Start screen capture or add heroes manually to see recommendations."
                )
            } else {
                ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, rec in
                    RecommendationCard(recommendation: rec, rank: index + 1) {
                        onSelect(rec)
                    }
                }
            }
        }
    }
}

// MARK: - Recommendation Card
struct RecommendationCard: View {
    let recommendation: HeroRecommendation
    let rank: Int
    let onTap: () -> Void
    @State private var isExpanded: Bool = false

    var body: some View {
        Button(action: onTap) {
            GlassCard {
                VStack(spacing: 12) {
                    // Header row
                    HStack(spacing: 12) {
                        RankBadge(rank: rank)
                        HeroAvatarView(hero: recommendation.hero, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recommendation.hero.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(recommendation.hero.primaryRole.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            ScoreDisplay(score: recommendation.scores.overallScore)
                            ConfidenceBar(confidence: recommendation.scores.confidence)
                                .frame(width: 80)
                        }
                    }

                    // Reason
                    Text(recommendation.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Score breakdown (collapsed)
                    ScoreBreakdownView(scores: recommendation.scores)
                        .padding(.top, 4)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Team Analysis Panel
struct TeamAnalysisPanel: View {
    let analysis: TeamCompositionAnalysis

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Friendly Composition")
            compositionGrid
            if !analysis.weaknesses.isEmpty {
                weaknessSection
            }
            if !analysis.suggestions.isEmpty {
                suggestionSection
            }
        }
    }

    private var compositionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatBarRow(label: "Frontline", value: analysis.frontlineScore)
            StatBarRow(label: "Backline", value: analysis.backlineScore)
            StatBarRow(label: "Magic DMG", value: analysis.magicDamageScore)
            StatBarRow(label: "Physical DMG", value: analysis.physicalDamageScore)
            StatBarRow(label: "Burst", value: analysis.burstScore)
            StatBarRow(label: "Sustain", value: analysis.sustainScore)
            StatBarRow(label: "Crowd Control", value: analysis.crowdControlScore)
            StatBarRow(label: "Wave Clear", value: analysis.waveClearScore)
            StatBarRow(label: "Objectives", value: analysis.objectiveControlScore)
            StatBarRow(label: "Scaling", value: analysis.scalingScore)
        }
    }

    private var weaknessSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Weaknesses", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                ForEach(analysis.weaknesses, id: \.self) { weakness in
                    HStack(spacing: 8) {
                        Circle().fill(.orange).frame(width: 4, height: 4)
                        Text(weakness).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
    }

    private var suggestionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Suggestions", systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.hayaGold)
                ForEach(analysis.suggestions, id: \.self) { suggestion in
                    HStack(spacing: 8) {
                        Circle().fill(Color.hayaGold).frame(width: 4, height: 4)
                        Text(suggestion).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Strategy Panel
struct StrategyPanel: View {
    let strategy: DraftStrategy?

    var body: some View {
        if let strategy {
            VStack(spacing: 12) {
                StrategyCard(title: "Early Game", icon: "sunrise.fill", color: .orange, content: strategy.earlyGamePlan)
                StrategyCard(title: "Mid Game", icon: "sun.max.fill", color: .yellow, content: strategy.midGamePlan)
                StrategyCard(title: "Late Game", icon: "moon.stars.fill", color: .hayaBlue, content: strategy.lateGamePlan)

                if !strategy.teamfightAdvice.isEmpty {
                    StrategyCard(title: "Teamfight", icon: "bolt.fill", color: .purple, content: strategy.teamfightAdvice)
                }
                if !strategy.turtleTiming.isEmpty {
                    StrategyCard(title: "Turtle Timing", icon: "tortoise.fill", color: .green, content: strategy.turtleTiming)
                }
                if !strategy.lordTiming.isEmpty {
                    StrategyCard(title: "Lord Timing", icon: "crown.fill", color: .hayaGold, content: strategy.lordTiming)
                }
            }
        } else {
            EmptyStateCard(
                icon: "map.fill",
                title: "No Strategy Yet",
                message: "Add heroes to your team to generate a strategy guide."
            )
        }
    }
}

struct StrategyCard: View {
    let title: String
    let icon: String
    let color: Color
    let content: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }
}

// MARK: - Manual Draft Panel
struct ManualDraftPanel: View {
    var body: some View {
        EmptyStateCard(
            icon: "pencil.and.list.clipboard",
            title: "Manual Draft Entry",
            message: "Tap any slot in the draft board to manually add or remove heroes."
        )
    }
}

// MARK: - Recommendation Detail Sheet
struct RecommendationDetailSheet: View {
    let recommendation: HeroRecommendation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        heroHeader
                        scoreBreakdown
                        buildSection
                        advantagesSection
                        weaknessesSection
                        spellEmblemSection
                        strategyNote
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(recommendation.hero.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var heroHeader: some View {
        GlassCard {
            HStack(spacing: 16) {
                HeroAvatarView(hero: recommendation.hero, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.hero.name)
                        .font(.title2).fontWeight(.bold)
                    HStack(spacing: 6) {
                        RoleBadge(role: recommendation.hero.primaryRole)
                        LaneBadge(lane: recommendation.hero.primaryLane)
                    }
                    HStack(spacing: 4) {
                        Text("Overall Score:")
                            .font(.caption).foregroundStyle(.secondary)
                        ScoreDisplay(score: recommendation.scores.overallScore)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private var scoreBreakdown: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Score Breakdown")
                    .font(.subheadline).fontWeight(.semibold)
                ScoreBreakdownView(scores: recommendation.scores)
            }
            .padding(14)
        }
    }

    private var buildSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Recommended Build", systemImage: "hammer.fill")
                    .font(.subheadline).fontWeight(.semibold)
                ForEach(recommendation.suggestedBuild.coreItems) { item in
                    ItemRow(item: item, isSituational: false)
                }
                if !recommendation.suggestedBuild.situationalItems.isEmpty {
                    Text("Situational")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(recommendation.suggestedBuild.situationalItems) { item in
                        ItemRow(item: item, isSituational: true)
                    }
                }
            }
            .padding(14)
        }
    }

    private var advantagesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Advantages", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                ForEach(recommendation.advantages, id: \.self) { adv in
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.caption)
                        Text(adv).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private var weaknessesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Weaknesses", systemImage: "exclamationmark.shield.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.orange)
                ForEach(recommendation.weaknesses, id: \.self) { w in
                    HStack(spacing: 8) {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.orange).font(.caption)
                        Text(w).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private var spellEmblemSection: some View {
        HStack(spacing: 12) {
            GlassCard {
                VStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow).font(.title3)
                    Text("Spell")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(recommendation.suggestedSpell.rawValue)
                        .font(.caption).fontWeight(.semibold)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
            GlassCard {
                VStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.hayaGold).font(.title3)
                    Text("Emblem")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(recommendation.suggestedEmblem.rawValue)
                        .font(.caption).fontWeight(.semibold)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var strategyNote: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Strategy Note", systemImage: "lightbulb.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.hayaGold)
                Text(recommendation.strategyNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }
}
