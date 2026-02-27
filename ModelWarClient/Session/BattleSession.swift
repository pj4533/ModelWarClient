import Foundation

@Observable
final class BattleSession {
    var currentBattle: ChallengeResponse?
    var currentReplay: BattleReplay?
    var isLoadingReplay = false
    var selectedRound: Int = 1

    private let consoleLog: ConsoleLog

    init(consoleLog: ConsoleLog) {
        self.consoleLog = consoleLog
    }

    func setBattle(_ battle: ChallengeResponse) {
        currentBattle = battle
        selectedRound = 1
        consoleLog.log("Battle \(battle.battleId): \(battle.result) (\(battle.challengerWins)W-\(battle.defenderWins)L-\(battle.ties)T)", category: "Battle")
    }

    func loadReplay(battleId: Int, apiClient: APIClient) async {
        isLoadingReplay = true
        do {
            let replay = try await apiClient.fetchReplay(battleId: battleId)
            self.currentReplay = replay
            self.isLoadingReplay = false
            consoleLog.log("Replay loaded for battle \(battleId)", category: "Battle")
        } catch {
            self.isLoadingReplay = false
            consoleLog.log("Failed to load replay: \(error.localizedDescription)", level: .error, category: "Battle")
        }
    }

    func clear() {
        currentBattle = nil
        currentReplay = nil
        selectedRound = 1
    }
}
