import SwiftUI

struct LeaderboardView: View {
    @Bindable var appSession: AppSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Leaderboard")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    appSession.fetchLeaderboard()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

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
                                .foregroundStyle(.blue)
                                .underline()
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                                .onTapGesture {
                                    appSession.fetchPlayerProfile(id: entry.id)
                                }
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
                    .width(50)

                    TableColumn("") { entry in
                        if !isCurrentPlayer(entry) {
                            Button("Challenge") {
                                appSession.challenge(defenderId: entry.id, defenderName: entry.name)
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
        .onAppear {
            if appSession.leaderboard.isEmpty {
                appSession.fetchLeaderboard()
            }
        }
        .sheet(isPresented: $appSession.showingBattleResult) {
            BattleResultView(appSession: appSession)
        }
    }

    private func isCurrentPlayer(_ entry: LeaderboardEntry) -> Bool {
        entry.id == appSession.player?.id
    }
}
