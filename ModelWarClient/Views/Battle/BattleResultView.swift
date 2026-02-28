import SwiftUI

struct BattleResultView: View {
    @Bindable var appSession: AppSession

    var body: some View {
        VStack(spacing: 0) {
            if let result = appSession.lastChallengeResult {
                resultsView(result)
            } else {
                loadingView
            }
        }
        .frame(width: 500, height: 480)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Challenging \(appSession.challengeDefenderName)...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private func resultsView(_ result: ChallengeResponse) -> some View {
        VStack(spacing: 16) {
            resultHeader(result)
            ratingChangesSection(result)
            roundsTable(result)
            doneButton
        }
        .padding()
    }

    private func resultHeader(_ result: ChallengeResponse) -> some View {
        VStack(spacing: 4) {
            Text(headerTitle(for: result.result))
                .font(.title.bold())
                .foregroundStyle(headerColor(for: result.result))
            Text("\(result.challengerWins) - \(result.defenderWins) - \(result.ties)")
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("W - L - T")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func ratingChangesSection(_ result: ChallengeResponse) -> some View {
        Group {
            if let changes = result.ratingChanges {
                VStack(spacing: 6) {
                    ratingRow(name: changes.challenger.name, change: changes.challenger)
                    ratingRow(name: changes.defender.name, change: changes.defender)
                }
                .padding(.horizontal)
            }
        }
    }

    private func ratingRow(name: String, change: ChallengeResponse.RatingChanges.RatingChange) -> some View {
        HStack {
            Text(name)
                .fontWeight(.medium)
            Spacer()
            Text("\(Int(change.before))")
                .monospacedDigit()
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(change.after))")
                .monospacedDigit()
            Text(changeText(change.change))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(change.change >= 0 ? .green : .red)
                .frame(width: 50, alignment: .trailing)
        }
        .font(.callout)
    }

    private func roundsTable(_ result: ChallengeResponse) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Round")
                    .frame(width: 50, alignment: .leading)
                Text("Winner")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Replay")
                    .frame(width: 50, alignment: .center)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            if let replay = appSession.challengeReplay {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(replay.roundResults) { round in
                            roundRow(round, battleId: result.battleId)
                            if round.round < replay.roundResults.count {
                                Divider()
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading rounds...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private func roundRow(_ round: BattleReplay.RoundResult, battleId: Int) -> some View {
        HStack {
            Text("\(round.round)")
                .monospacedDigit()
                .frame(width: 50, alignment: .leading)
            Text(round.winner)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(roundWinnerColor(round.winner))
            Button {
                let url = URL(string: "https://www.modelwar.ai/battles/\(battleId)/rounds/\(round.round)")!
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "play.circle")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .frame(width: 50, alignment: .center)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    private var doneButton: some View {
        Button("Done") {
            appSession.dismissBattleResult()
        }
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
    }

    // MARK: - Helpers

    private func headerTitle(for result: String) -> String {
        switch result {
        case "win": return "Victory!"
        case "loss": return "Defeat"
        case "tie": return "Draw"
        default: return result.capitalized
        }
    }

    private func headerColor(for result: String) -> Color {
        switch result {
        case "win": return .green
        case "loss": return .red
        case "tie": return .orange
        default: return .primary
        }
    }

    private func changeText(_ change: Double) -> String {
        let intChange = Int(change)
        return intChange >= 0 ? "(+\(intChange))" : "(\(intChange))"
    }

    private func roundWinnerColor(_ winner: String) -> Color {
        switch winner {
        case "tie": return .orange
        default: return .primary
        }
    }
}
