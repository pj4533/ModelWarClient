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
                // Column header row
                HStack(spacing: 0) {
                    Text("#")
                        .frame(width: 36, alignment: .leading)
                    Text("Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Rating")
                        .frame(width: 56, alignment: .trailing)
                    Spacer()
                        .frame(width: 80)
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 4)

                Divider()

                List {
                    ForEach(appSession.leaderboard) { entry in
                        LeaderboardRowView(
                            entry: entry,
                            isCurrentPlayer: isCurrentPlayer(entry),
                            isChallengeDisabled: appSession.isChallenging || appSession.apiKey == nil,
                            onTapName: {
                                appSession.fetchPlayerProfile(id: entry.id)
                            },
                            onChallenge: {
                                appSession.challenge(defenderId: entry.id, defenderName: entry.name)
                            }
                        )
                        .onAppear {
                            let lastId = appSession.leaderboard.last?.id
                            appSession.consoleLog.log("Row appeared: rank=\(entry.rank) id=\(entry.id), lastId=\(lastId ?? -1), match=\(entry.id == lastId)", level: .debug, category: "Leaderboard")
                            if entry.id == lastId {
                                appSession.consoleLog.log("Last row visible — triggering loadMore", category: "Leaderboard")
                                appSession.loadMoreLeaderboard()
                            }
                        }
                    }

                    if appSession.isLoadingMoreLeaderboard {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading more...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
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

// MARK: - Row View

private struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let isCurrentPlayer: Bool
    let isChallengeDisabled: Bool
    let onTapName: () -> Void
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("\(entry.rank)")
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)

            HStack(spacing: 4) {
                Text(entry.name)
                    .fontWeight(isCurrentPlayer ? .bold : .regular)
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
                        onTapName()
                    }
                if isCurrentPlayer {
                    Text("(you)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(Int(entry.rating))")
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)

            if !isCurrentPlayer {
                Button("Challenge") {
                    onChallenge()
                }
                .disabled(isChallengeDisabled)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: 80)
            } else {
                Spacer()
                    .frame(width: 80)
            }
        }
    }
}
