import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var settings = UserSettings()
    @State private var showSignOutAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                List {
                    profileSection
                    draftSection
                    displaySection
                    dataSection
                    accountSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private var profileSection: some View {
        Section {
            if let profile = authService.currentProfile {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color.hayaGold, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 52, height: 52)
                        Text(String(profile.displayName.prefix(1)))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.headline)
                        Text(profile.email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        } header: { Text("Profile") }
    }

    private var draftSection: some View {
        Section {
            Toggle("Auto-detect Draft", isOn: $settings.autoDetectDraft)
            Stepper("Recommendations: \(settings.recommendationCount)", value: $settings.recommendationCount, in: 3...10)
            Toggle("Show Confidence Bars", isOn: $settings.showConfidenceBars)
            Toggle("Show Detailed Scores", isOn: $settings.showDetailedScores)
        } header: { Text("Draft Assistant") }
    }

    private var displaySection: some View {
        Section {
            Toggle("Haptic Feedback", isOn: $settings.enableHaptics)
            Toggle("Sound Effects", isOn: $settings.enableSounds)
            HStack {
                Text("Overlay Opacity")
                Slider(value: $settings.overlayOpacity, in: 0.5...1.0)
                Text(String(format: "%.0f%%", settings.overlayOpacity * 100))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
        } header: { Text("Display") }
    }

    private var dataSection: some View {
        Section {
            Toggle("Usage Analytics", isOn: $settings.dataCollection)
            Picker("Notifications", selection: $settings.notificationFrequency) {
                ForEach(NotificationFrequency.allCases, id: \.self) { freq in
                    Text(freq.rawValue).tag(freq)
                }
            }
        } header: { Text("Data & Privacy") }
    }

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: { Text("Account") }
    }
}
