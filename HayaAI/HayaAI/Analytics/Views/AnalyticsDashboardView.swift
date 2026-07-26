import SwiftUI
import Charts

struct AnalyticsDashboardView: View {
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                ScrollView {
                    VStack(spacing: 20) {
                        statsGrid
                        winRateChart
                        recentMatchesSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Analytics")
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Drafts Analyzed", value: "0", icon: "shield.lefthalf.filled", color: .hayaBlue)
            StatCard(title: "Win Rate", value: "—", icon: "chart.bar.fill", color: .hayaGold)
            StatCard(title: "Rec. Accuracy", value: "—", icon: "target", color: .green)
            StatCard(title: "Fav. Role", value: "—", icon: "star.fill", color: .purple)
        }
    }

    private var winRateChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Win Rate by Role")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                Chart {
                    ForEach(HeroRole.allCases, id: \.self) { role in
                        BarMark(
                            x: .value("Role", role.rawValue),
                            y: .value("Win Rate", Double.random(in: 0.45...0.65))
                        )
                        .foregroundStyle(roleColor(role))
                    }
                }
                .frame(height: 150)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recent Matches")
            EmptyStateCard(
                icon: "clock.fill",
                title: "No Matches Yet",
                message: "Your match history will appear here after you start analyzing drafts."
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.title3)
                    Spacer()
                }
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }
}
