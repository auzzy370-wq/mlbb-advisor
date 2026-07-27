import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var heroDatabaseService: HeroDatabaseService

    var body: some View {
        NavigationStack(path: $appRouter.navigationPath) {
            ZStack {
                HayaBackground()
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        quickActionSection
                        metaTierSection
                        patchSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Haya AI")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome back,")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(authService.currentProfile?.displayName ?? "Player")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Quick Actions")
            HStack(spacing: 12) {
                QuickActionCard(
                    title: "Start Draft",
                    subtitle: "Analyze live draft",
                    icon: "shield.lefthalf.filled",
                    color: Color.hayaBlue
                ) {
                    appRouter.switchTab(.draftAssistant)
                }
                QuickActionCard(
                    title: "Meta Picks",
                    subtitle: "Current patch S-tier",
                    icon: "star.fill",
                    color: Color.hayaGold
                ) {
                    appRouter.switchTab(.analytics)
                }
            }
        }
    }

    // Top 9 heroes sorted live from the auto-updating database service.
    private var topMetaHeroes: [Hero] {
        heroDatabaseService.heroes
            .sorted { $0.metaScore > $1.metaScore }
            .prefix(9)
            .map { $0 }
    }

    private var metaTierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Meta Heroes — Patch \(heroDatabaseService.currentPatch)",
                          action: { appRouter.switchTab(.analytics) })

            if !heroDatabaseService.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else if topMetaHeroes.isEmpty {
                Text("Loading hero database…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(topMetaHeroes) { hero in
                        MetaHeroCard(hero: hero)
                    }
                }
            }
        }
    }

    private var patchSection: some View {
        GlassCard {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    // Patch info
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Patch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(heroDatabaseService.currentPatch)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        if let lastChecked = heroDatabaseService.lastChecked {
                            Text("Updated \(lastChecked, style: .relative) ago")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Tap to check for updates")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Hero count badge
                    VStack(spacing: 2) {
                        Text("\(heroDatabaseService.heroes.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.hayaGold)
                        Text("heroes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // Refresh button
                    Button {
                        Task { await heroDatabaseService.refreshFromRemote() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.hayaBlue.opacity(0.15))
                                .frame(width: 38, height: 38)
                            if heroDatabaseService.isCheckingForUpdates {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(Color.hayaBlue)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.hayaBlue)
                            }
                        }
                    }
                    .disabled(heroDatabaseService.isCheckingForUpdates)
                }
                .padding(16)

                // Live update status strip
                if heroDatabaseService.isCheckingForUpdates {
                    Divider().opacity(0.2)
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Checking for meta updates…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var profileButton: some View {
        Button {
            appRouter.present(.profile)
        } label: {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.hayaGold)
        }
    }
}

// MARK: - Meta Hero Card
struct MetaHeroCard: View {
    let hero: Hero

    var body: some View {
        GlassCard {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(roleColor(hero.primaryRole).opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: roleIcon(hero.primaryRole))
                        .font(.title3)
                        .foregroundStyle(roleColor(hero.primaryRole))
                        .frame(width: 44, height: 44)

                    // Tier badge
                    Text(tierLabel(hero.metaScore))
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(tierColor(hero.metaScore))
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
                Text(hero.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(hero.primaryRole.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(roleColor(hero.primaryRole))
            }
            .padding(10)
        }
    }

    private func tierLabel(_ score: Double) -> String {
        switch score {
        case 9.5...: return "S+"
        case 9.0..<9.5: return "S"
        case 8.0..<9.0: return "A"
        default: return "B"
        }
    }

    private func tierColor(_ score: Double) -> Color {
        switch score {
        case 9.5...: return .red
        case 9.0..<9.5: return .orange
        case 8.0..<9.0: return Color.hayaBlue
        default: return .gray
        }
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }
}
