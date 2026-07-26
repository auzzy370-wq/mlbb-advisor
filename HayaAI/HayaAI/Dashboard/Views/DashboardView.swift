import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @EnvironmentObject private var appRouter: AppRouter

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

    private var metaTierSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Meta Heroes", action: { appRouter.switchTab(.analytics) })

            if dashboardViewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(dashboardViewModel.topMetaHeroes.prefix(9)) { hero in
                        MetaHeroCard(hero: hero)
                    }
                }
            }
        }
    }

    private var patchSection: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Patch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dashboardViewModel.currentPatch)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(Color.hayaGold)
            }
            .padding(16)
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
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(roleColor(hero.primaryRole).opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: roleIcon(hero.primaryRole))
                        .font(.title3)
                        .foregroundStyle(roleColor(hero.primaryRole))
                }
                Text(hero.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                MetaScoreBadge(score: hero.metaScore)
            }
            .padding(10)
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
