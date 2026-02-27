import Foundation

@Observable
final class AppSession {
    var apiKey: String?
    var player: Player?
    var warriorCode: String = RedcodeTemplates.imp
    var warriorName: String = "MyWarrior"
    var showingSettings = false
    var showingLeaderboard = false
    var leaderboard: [LeaderboardEntry] = []
    var isLoading = false
    var isChallenging = false
    var isUploading = false

    let consoleLog = ConsoleLog()
    let apiClient = APIClient()
    private(set) var battleSession: BattleSession!
    private(set) var agentSession: AgentSession!

    init() {
        battleSession = BattleSession(consoleLog: consoleLog)
        agentSession = AgentSession(consoleLog: consoleLog)
        loadApiKey()
    }

    // MARK: - API Key Management

    func loadApiKey() {
        if let key = KeychainService.load() {
            apiKey = key
            consoleLog.log("API key loaded from Keychain", category: "Auth")
            Task {
                await apiClient.setApiKey(key)
                await fetchProfileAsync()
            }
        } else {
            consoleLog.log("No API key found", level: .debug, category: "Auth")
            showingSettings = true
        }
    }

    func setApiKey(_ key: String) {
        apiKey = key
        _ = KeychainService.save(apiKey: key)
        consoleLog.log("API key saved", category: "Auth")
        Task {
            await apiClient.setApiKey(key)
            await fetchProfileAsync()
        }
        syncAgentContext()
    }

    func clearApiKey() {
        apiKey = nil
        player = nil
        KeychainService.delete()
        Task { await apiClient.setApiKey(nil) }
        consoleLog.log("API key cleared", category: "Auth")
    }

    // MARK: - Profile

    func fetchProfile() {
        Task { await fetchProfileAsync() }
    }

    private func fetchProfileAsync() async {
        do {
            let profile = try await apiClient.fetchProfile()
            await MainActor.run {
                self.player = profile
                if let warrior = profile.warrior {
                    self.warriorCode = warrior.redcode
                    self.warriorName = warrior.name
                }
                self.consoleLog.log("Profile loaded: \(profile.name) (rating: \(Int(profile.rating)))", category: "API")
            }
        } catch {
            consoleLog.log("Failed to load profile: \(error.localizedDescription)", level: .error, category: "API")
        }
    }

    // MARK: - Leaderboard

    func fetchLeaderboard() {
        Task {
            do {
                let response = try await apiClient.fetchLeaderboard()
                await MainActor.run {
                    self.leaderboard = response.leaderboard
                    self.consoleLog.log("Leaderboard loaded: \(response.totalPlayers) players", category: "API")
                }
            } catch {
                consoleLog.log("Failed to load leaderboard: \(error.localizedDescription)", level: .error, category: "API")
            }
        }
    }

    // MARK: - Warrior Upload

    func uploadWarrior() {
        guard !warriorCode.isEmpty else { return }
        isUploading = true

        Task {
            do {
                let warrior = try await apiClient.uploadWarrior(name: warriorName, redcode: warriorCode)
                await MainActor.run {
                    self.isUploading = false
                    self.consoleLog.log("Warrior '\(warrior.name)' uploaded (\(warrior.instructionCount ?? 0) instructions)", category: "API")
                    self.fetchProfile()
                }
            } catch {
                await MainActor.run {
                    self.isUploading = false
                    self.consoleLog.log("Upload failed: \(error.localizedDescription)", level: .error, category: "API")
                }
            }
        }
    }

    // MARK: - Challenge

    func challenge(defenderId: Int) {
        isChallenging = true

        Task {
            do {
                let result = try await apiClient.challenge(defenderId: defenderId)
                await MainActor.run {
                    self.isChallenging = false
                    self.battleSession.setBattle(result)
                    self.consoleLog.log("Challenge result: \(result.result) (\(result.challengerWins)-\(result.defenderWins)-\(result.ties))", category: "Battle")
                    self.fetchProfile()
                }

                // Load replay
                await battleSession.loadReplay(battleId: result.battleId, apiClient: apiClient)

                // Sync context with agent after battle
                await MainActor.run {
                    let battleSummary = "Last battle: \(result.result) (\(result.challengerWins)W-\(result.defenderWins)L-\(result.ties)T)"
                    self.syncAgentContext(recentBattle: battleSummary)
                }
            } catch {
                await MainActor.run {
                    self.isChallenging = false
                    self.consoleLog.log("Challenge failed: \(error.localizedDescription)", level: .error, category: "Battle")
                }
            }
        }
    }

    // MARK: - Agent

    func startAgent() {
        agentSession.start()
        syncAgentContext()
    }

    func onWarriorCodeChanged() {
        syncAgentContext()
    }

    func syncAgentContext(recentBattle: String? = nil) {
        guard let apiKey, agentSession.isConnected else { return }
        agentSession.setContext(apiKey: apiKey, warriorCode: warriorCode, recentBattle: recentBattle)
    }

    func shutdown() {
        agentSession.shutdown()
    }
}
