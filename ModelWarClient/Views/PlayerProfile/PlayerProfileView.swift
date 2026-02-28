import SwiftUI

struct PlayerProfileView: View {
    @Bindable var appSession: AppSession

    var body: some View {
        VStack(spacing: 0) {
            if let profile = appSession.selectedPlayerProfile {
                profileContent(profile)
            } else {
                loadingView
            }
        }
        .frame(width: 700, height: 600)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading profile...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Profile Content

    private func profileContent(_ profile: PlayerProfile) -> some View {
        VStack(spacing: 0) {
            headerSection(profile)
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    statCardsSection(profile)
                    if let warrior = profile.warrior {
                        warriorSection(warrior)
                    }
                    battlesSection(profile)
                }
                .padding()
            }
            Divider()
            closeButton
        }
    }

    // MARK: - Header

    private func headerSection(_ profile: PlayerProfile) -> some View {
        HStack {
            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.title2.bold())
                if profile.provisional {
                    Text("Provisional")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            Text("Joined: \(formattedJoinDate(profile.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Stat Cards

    private func statCardsSection(_ profile: PlayerProfile) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                statCard(title: "Rating", value: "\(Int(profile.rating))", color: .blue)
                statCard(title: "Wins", value: "\(profile.wins)", color: .green)
                statCard(title: "Losses", value: "\(profile.losses)", color: .red)
                statCard(title: "Ties", value: "\(profile.ties)", color: .orange)
            }
            HStack {
                Text("Win Rate: \(String(format: "%.1f", profile.winRate))%")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Record: \(profile.wins)-\(profile.losses)-\(profile.ties)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Warrior

    private func warriorSection(_ warrior: PlayerProfile.ProfileWarrior) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Warrior: \(warrior.name)")
                .font(.callout.bold())
            ReadOnlyCodeView(code: warrior.redcode)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
        }
    }

    // MARK: - Battles

    private func battlesSection(_ profile: PlayerProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Battles")
                .font(.callout.bold())

            if profile.recentBattles.isEmpty {
                Text("No recent battles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Date")
                            .frame(width: 80, alignment: .leading)
                        Text("Opponent")
                            .frame(width: 120, alignment: .leading)
                        Text("Result")
                            .frame(width: 60, alignment: .center)
                        Text("Score")
                            .frame(width: 80, alignment: .center)
                        Text("Rating")
                            .frame(width: 60, alignment: .trailing)
                        Spacer()
                        Text("")
                            .frame(width: 30)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)

                    Divider()

                    ForEach(profile.recentBattles) { battle in
                        battleRow(battle)
                        if battle.id != profile.recentBattles.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator, lineWidth: 1)
                )
            }
        }
    }

    private func battleRow(_ battle: PlayerProfile.RecentBattle) -> some View {
        HStack(spacing: 0) {
            Text(formattedBattleDate(battle.createdAt))
                .frame(width: 80, alignment: .leading)
            Text(battle.opponent?.name ?? battle.matchup ?? "Arena")
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            Text(battle.result.capitalized)
                .foregroundStyle(resultColor(battle.result))
                .frame(width: 60, alignment: .center)
            Text(battle.score)
                .monospacedDigit()
                .frame(width: 80, alignment: .center)
            Text(ratingChangeText(battle.ratingChange))
                .monospacedDigit()
                .foregroundStyle(battle.ratingChange >= 0 ? .green : .red)
                .frame(width: 60, alignment: .trailing)
            Spacer()
            Button {
                let url = URL(string: "https://www.modelwar.ai/battles/\(battle.id)")!
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "arrow.up.right.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Close

    private var closeButton: some View {
        HStack {
            Spacer()
            Button("Close") {
                appSession.dismissPlayerProfile()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Helpers

    private func formattedJoinDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return dateString }
            return formatDate(date, style: .medium)
        }
        return formatDate(date, style: .medium)
    }

    private func formattedBattleDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateString) else { return dateString }
            return formatDate(date, style: .short)
        }
        return formatDate(date, style: .short)
    }

    private func formatDate(_ date: Date, style: DateFormatter.Style) -> String {
        let df = DateFormatter()
        df.dateStyle = style
        df.timeStyle = .none
        return df.string(from: date)
    }

    private func resultColor(_ result: String) -> Color {
        switch result {
        case "win": return .green
        case "loss": return .red
        case "tie": return .orange
        default: return .primary
        }
    }

    private func ratingChangeText(_ change: Double) -> String {
        let intChange = Int(change)
        return intChange >= 0 ? "+\(intChange)" : "\(intChange)"
    }
}
