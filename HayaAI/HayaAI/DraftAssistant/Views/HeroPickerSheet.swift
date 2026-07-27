import SwiftUI

// MARK: - Slot Target
/// Describes the exact draft slot the picker is filling.
struct DraftSlotTarget: Identifiable {
    enum SlotKind { case pick, ban }
    let id = UUID()
    let team: DraftTurn
    let slot: Int
    let kind: SlotKind
}

// MARK: - Hero Picker Sheet
/// Full-screen hero search & selection sheet.
/// Opened by tapping any empty (or filled) draft slot.
struct HeroPickerSheet: View {
    let target: DraftSlotTarget
    let heroDatabase: HeroDatabaseService
    let onPick: (String) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var roleFilter: HeroRole? = nil
    @State private var heroes: [Hero] = []
    @State private var filtered: [Hero] = []

    var body: some View {
        NavigationStack {
            ZStack {
                HayaBackground()
                VStack(spacing: 0) {
                    // ── Search bar ────────────────────────────────────────
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search hero…", text: $query)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: query) { _, _ in applyFilter() }
                    }
                    .padding(11)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // ── Role filter chips ─────────────────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            RoleChip(label: "All", isSelected: roleFilter == nil) {
                                roleFilter = nil; applyFilter()
                            }
                            ForEach(HeroRole.allCases, id: \.self) { role in
                                RoleChip(label: role.rawValue,
                                         color: roleColor(role),
                                         isSelected: roleFilter == role) {
                                    roleFilter = (roleFilter == role) ? nil : role
                                    applyFilter()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    Divider().opacity(0.3)

                    // ── Hero grid ─────────────────────────────────────────
                    if filtered.isEmpty {
                        Spacer()
                        Text("No heroes found")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 90, maximum: 110))],
                                spacing: 12
                            ) {
                                ForEach(filtered) { hero in
                                    HeroPickerCell(hero: hero) {
                                        onPick(hero.name)
                                        dismiss()
                                    }
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle(pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear slot", role: .destructive) {
                        onClear()
                        dismiss()
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            heroes = await heroDatabase.searchHeroes(query: "")
            applyFilter()
        }
    }

    // MARK: - Helpers

    private var pickerTitle: String {
        let teamLabel = target.team == .friendly ? "Ally" : "Enemy"
        let kindLabel = target.kind == .ban ? "Ban" : "Pick"
        return "\(teamLabel) \(kindLabel) \(target.slot + 1)"
    }

    private func applyFilter() {
        var base = heroes
        if let role = roleFilter {
            base = base.filter { $0.primaryRole == role || $0.secondaryRole == role }
        }
        if !query.isEmpty {
            let lower = query.lowercased()
            base = base.filter {
                $0.name.lowercased().contains(lower) ||
                $0.primaryRole.rawValue.lowercased().contains(lower)
            }
        }
        filtered = base.sorted { $0.metaScore > $1.metaScore }
    }

    private func roleColor(_ role: HeroRole) -> Color {
        switch role {
        case .fighter:   return .orange
        case .tank:      return .blue
        case .assassin:  return .red
        case .mage:      return .purple
        case .marksman:  return .yellow
        case .support:   return .green
        }
    }
}

// MARK: - Role Filter Chip
private struct RoleChip: View {
    let label: String
    var color: Color = .hayaBlue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.25) : Color.white.opacity(0.06))
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero Picker Cell
private struct HeroPickerCell: View {
    let hero: Hero
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(roleColor(hero.primaryRole).opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(roleColor(hero.primaryRole).opacity(0.35), lineWidth: 1)
                        )
                        .frame(height: 60)

                    VStack(spacing: 2) {
                        Text(heroInitials(hero.name))
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(roleColor(hero.primaryRole))
                        // Meta score dot indicator
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle()
                                    .fill(Double(i) < hero.metaScore / 2
                                          ? roleColor(hero.primaryRole)
                                          : Color.white.opacity(0.15))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }

                Text(hero.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(hero.primaryRole.rawValue)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func heroInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    private func roleColor(_ role: HeroRole) -> Color {
        switch role {
        case .fighter:   return .orange
        case .tank:      return .blue
        case .assassin:  return .red
        case .mage:      return .purple
        case .marksman:  return .yellow
        case .support:   return .green
        }
    }
}
