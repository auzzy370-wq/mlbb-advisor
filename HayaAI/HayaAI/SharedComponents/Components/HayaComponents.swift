import SwiftUI

// MARK: - Haya Button
struct HayaButton: View {
    enum ButtonStyle { case primary, secondary, destructive }

    let title: String
    var isLoading: Bool = false
    var style: ButtonStyle = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Text(title)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(buttonBackground)
            .foregroundStyle(buttonForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(buttonBorder, lineWidth: 1)
            )
        }
        .disabled(isLoading)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }

    private var buttonBackground: AnyShapeStyle {
        switch style {
        case .primary:
            return AnyShapeStyle(LinearGradient(colors: [Color.hayaGold, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .secondary:
            return AnyShapeStyle(Color.white.opacity(0.1))
        case .destructive:
            return AnyShapeStyle(Color.red.opacity(0.2))
        }
    }

    private var buttonForeground: Color {
        switch style {
        case .primary: return .black
        case .secondary: return .white
        case .destructive: return .red
        }
    }

    private var buttonBorder: Color {
        switch style {
        case .primary: return Color.hayaGold.opacity(0.5)
        case .secondary: return Color.white.opacity(0.2)
        case .destructive: return Color.red.opacity(0.5)
        }
    }
}

// MARK: - Haya Text Field
struct HayaTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.hayaGold)
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Haya Secure Field
struct HayaSecureField: View {
    @Binding var text: String
    let placeholder: String
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(Color.hayaGold)
                .frame(width: 20)
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .foregroundStyle(.primary)
            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Logo Header
struct LogoHeader: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.hayaGold, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.hayaGold.opacity(0.4), radius: 20)
                Image(systemName: "shield.lefthalf.filled.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.black)
            }
            Text("Haya AI")
                .font(.largeTitle)
                .fontWeight(.heavy)
                .foregroundStyle(
                    LinearGradient(colors: [Color.hayaGold, .white], startPoint: .top, endPoint: .bottom)
                )
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            if let action {
                Button("See All", action: action)
                    .font(.caption)
                    .foregroundStyle(Color.hayaGold)
            }
        }
    }
}

// MARK: - Error Banner
struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
    }
}

// MARK: - Confidence Bar
struct ConfidenceBar: View {
    let confidence: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(confidenceColor)
                    .frame(width: geo.size.width * confidence)
                    .animation(.spring(response: 0.5), value: confidence)
            }
        }
        .frame(height: 4)
    }

    private var confidenceColor: Color {
        if confidence > 0.75 { return .green }
        if confidence > 0.5 { return .hayaGold }
        return .orange
    }
}

// MARK: - Score Display
struct ScoreDisplay: View {
    let score: Double

    var body: some View {
        Text(String(format: "%.1f", score))
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(scoreColor)
    }

    private var scoreColor: Color {
        if score >= 8 { return .green }
        if score >= 6 { return .hayaGold }
        return .orange
    }
}

// MARK: - Rank Badge
struct RankBadge: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(rankColor.opacity(0.2))
                .frame(width: 28, height: 28)
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.heavy)
                .foregroundStyle(rankColor)
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .hayaGold
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)
        default: return .secondary
        }
    }
}

// MARK: - Role Badge
struct RoleBadge: View {
    let role: HeroRole

    var body: some View {
        Text(role.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(roleColor(role).opacity(0.2))
            .foregroundStyle(roleColor(role))
            .clipShape(Capsule())
    }
}

// MARK: - Lane Badge
struct LaneBadge: View {
    let lane: HeroLane

    var body: some View {
        Text(lane.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.hayaBlue.opacity(0.2))
            .foregroundStyle(Color.hayaBlue)
            .clipShape(Capsule())
    }
}

// MARK: - Meta Score Badge
struct MetaScoreBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text(String(format: "%.1f", score))
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(scoreColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(scoreColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var scoreColor: Color {
        if score >= 9 { return .green }
        if score >= 7 { return .hayaGold }
        return .orange
    }
}

// MARK: - Hero Avatar
struct HeroAvatarView: View {
    let hero: Hero
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(roleColor(hero.primaryRole).opacity(0.2))
                .frame(width: size, height: size)
            Circle()
                .stroke(roleColor(hero.primaryRole).opacity(0.5), lineWidth: 2)
                .frame(width: size, height: size)
            Text(String(hero.name.prefix(2)))
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(roleColor(hero.primaryRole))
        }
    }
}

// MARK: - Score Breakdown
struct ScoreBreakdownView: View {
    let scores: HeroScoreComponents

    var body: some View {
        VStack(spacing: 6) {
            ScoreRow(label: "Counter", value: scores.counterScore)
            ScoreRow(label: "Synergy", value: scores.synergyScore)
            ScoreRow(label: "Lane Fit", value: scores.laneScore)
            ScoreRow(label: "Meta", value: scores.metaScore)
            ScoreRow(label: "Scaling", value: scores.scalingScore)
        }
    }
}

struct ScoreRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scoreBarColor(value))
                        .frame(width: geo.size.width * (value / 10.0))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
                }
            }
            .frame(height: 6)
            Text(String(format: "%.0f", value))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(scoreBarColor(value))
                .frame(width: 20, alignment: .trailing)
        }
    }

    private func scoreBarColor(_ value: Double) -> Color {
        if value >= 8 { return .green }
        if value >= 6 { return .hayaGold }
        return .orange
    }
}

// MARK: - Stat Bar Row
struct StatBarRow: View {
    let label: String
    let value: Double

    var body: some View {
        GlassCard(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", value))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(statColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(statColor)
                            .frame(width: geo.size.width * (value / 10.0))
                            .animation(.spring(response: 0.6), value: value)
                    }
                }
                .frame(height: 4)
            }
            .padding(8)
        }
    }

    private var statColor: Color {
        if value >= 8 { return .green }
        if value >= 5 { return .hayaGold }
        return .orange
    }
}

// MARK: - Item Row
struct ItemRow: View {
    let item: Item
    let isSituational: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(itemCategoryColor(item.category).opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: itemIcon(item.category))
                    .font(.caption)
                    .foregroundStyle(itemCategoryColor(item.category))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.caption)
                    .fontWeight(.medium)
                if let desc = item.description {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isSituational {
                Text("Sit.")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Loading Card
struct LoadingCard: View {
    let message: String

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Color.hayaGold)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Empty State Card
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.hayaGold.opacity(0.6))
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tab Selector Button
struct TabSelectorButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.hayaGold : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.hayaGold.opacity(0.15) : .clear)
                .clipShape(Capsule())
                .animation(.spring(response: 0.3), value: isSelected)
        }
    }
}

// MARK: - Splash View
struct SplashView: View {
    var body: some View {
        ZStack {
            HayaBackground()
            VStack(spacing: 16) {
                LogoHeader(subtitle: "Loading...")
                ProgressView()
                    .tint(Color.hayaGold)
            }
        }
    }
}

// MARK: - Helper Functions
func roleColor(_ role: HeroRole) -> Color {
    switch role {
    case .tank: return .blue
    case .fighter: return .orange
    case .assassin: return .purple
    case .mage: return Color(red: 0.6, green: 0.2, blue: 1.0)
    case .marksman: return .green
    case .support: return .cyan
    case .jungler: return Color(red: 0.5, green: 0.9, blue: 0.3)
    case .roamer: return .teal
    }
}

func roleIcon(_ role: HeroRole) -> String {
    switch role {
    case .tank: return "shield.fill"
    case .fighter: return "figure.martial.arts"
    case .assassin: return "bolt.fill"
    case .mage: return "sparkles"
    case .marksman: return "scope"
    case .support: return "heart.fill"
    case .jungler: return "leaf.fill"
    case .roamer: return "mappin.and.ellipse"
    }
}

func itemCategoryColor(_ category: ItemCategory) -> Color {
    switch category {
    case .physical: return .orange
    case .magic: return .purple
    case .defense: return .blue
    case .movement: return .green
    case .jungling: return Color(red: 0.4, green: 0.8, blue: 0.3)
    case .roaming: return .teal
    }
}

func itemIcon(_ category: ItemCategory) -> String {
    switch category {
    case .physical: return "flame.fill"
    case .magic: return "sparkles"
    case .defense: return "shield.fill"
    case .movement: return "hare.fill"
    case .jungling: return "leaf.fill"
    case .roaming: return "mappin.fill"
    }
}
