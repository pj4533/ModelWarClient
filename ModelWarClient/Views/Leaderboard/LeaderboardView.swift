import SwiftUI

struct LeaderboardView: View {
    @Bindable var appSession: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Leaderboard")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh") {
                    appSession.fetchLeaderboard()
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if appSession.leaderboard.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading leaderboard...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(appSession.leaderboard) {
                    TableColumn("#") { entry in
                        Text("\(entry.rank)")
                            .monospacedDigit()
                    }
                    .width(30)

                    TableColumn("Name") { entry in
                        HStack {
                            Text(entry.name)
                                .fontWeight(isCurrentPlayer(entry) ? .bold : .regular)
                            if isCurrentPlayer(entry) {
                                Text("(you)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 120)

                    TableColumn("Rating") { entry in
                        Text("\(Int(entry.rating))")
                            .monospacedDigit()
                    }
                    .width(60)

                    TableColumn("W/L/T") { entry in
                        Text("\(entry.wins)/\(entry.losses)/\(entry.ties)")
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(80)

                    TableColumn("") { entry in
                        if !isCurrentPlayer(entry) {
                            Button("Challenge") {
                                appSession.challenge(defenderId: entry.id)
                                dismiss()
                            }
                            .disabled(appSession.isChallenging || appSession.apiKey == nil)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .width(80)
                }
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if appSession.leaderboard.isEmpty {
                appSession.fetchLeaderboard()
            }
        }
    }

    private func isCurrentPlayer(_ entry: LeaderboardEntry) -> Bool {
        entry.id == appSession.player?.id
    }
}
