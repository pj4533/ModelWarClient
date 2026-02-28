import Foundation

@Observable
final class AppSession {
    var apiKey: String?
    var player: Player?
    var warriorCode: String = RedcodeTemplates.imp
    var warriorName: String = "MyWarrior"
    var showingSettings = false
    var leaderboard: [LeaderboardEntry] = []
    var isLoading = false
    var isChallenging = false
    var isUploading = false

    let consoleLog = ConsoleLog()
    let apiClient = APIClient()
    private(set) var agentSession: AgentSession!

    init() {
        agentSession = AgentSession(consoleLog: consoleLog)
        loadApiKey()
    }

    // MARK: - API Key Management

    func loadApiKey() {
        if let key = KeychainService.load() {
            apiKey = key
            apiClient.setApiKey(key)
            consoleLog.log("API key loaded from Keychain", category: "Auth")
            fetchProfile()
        } else {
            consoleLog.log("No API key found", level: .debug, category: "Auth")
            showingSettings = true
        }
    }

    func setApiKey(_ key: String) {
        apiKey = key
        _ = KeychainService.save(apiKey: key)
        apiClient.setApiKey(key)
        consoleLog.log("API key saved", category: "Auth")
        fetchProfile()
        syncAgentContext()
    }

    func clearApiKey() {
        apiKey = nil
        player = nil
        KeychainService.delete()
        apiClient.setApiKey(nil)
        consoleLog.log("API key cleared", category: "Auth")
    }

    // MARK: - Profile

    func fetchProfile() {
        Task {
            do {
                let profile = try await apiClient.fetchProfile()
                self.player = profile
                if let warrior = profile.warrior {
                    self.warriorCode = warrior.redcode
                    self.warriorName = warrior.name
                }
                self.consoleLog.log("Profile loaded: \(profile.name) (rating: \(Int(profile.rating)))", category: "API")
            } catch {
                consoleLog.log("Failed to load profile: \(error.localizedDescription)", level: .error, category: "API")
            }
        }
    }

    // MARK: - Leaderboard

    func fetchLeaderboard() {
        Task {
            do {
                let response = try await apiClient.fetchLeaderboard()
                self.leaderboard = response.leaderboard
                self.consoleLog.log("Leaderboard loaded: \(response.totalPlayers) players", category: "API")
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
                self.isUploading = false
                self.consoleLog.log("Warrior '\(warrior.name)' uploaded (\(warrior.instructionCount ?? 0) instructions)", category: "API")
                self.fetchProfile()
            } catch {
                self.isUploading = false
                self.consoleLog.log("Upload failed: \(error.localizedDescription)", level: .error, category: "API")
            }
        }
    }

    // MARK: - Challenge

    func challenge(defenderId: Int) {
        isChallenging = true

        Task {
            do {
                let result = try await apiClient.challenge(defenderId: defenderId)
                self.isChallenging = false
                self.consoleLog.log("Challenge result: \(result.result) (\(result.challengerWins)-\(result.defenderWins)-\(result.ties))", category: "Battle")
                self.fetchProfile()
                self.fetchLeaderboard()

                // Sync context with agent after battle
                let battleSummary = "Last battle: \(result.result) (\(result.challengerWins)W-\(result.defenderWins)L-\(result.ties)T)"
                self.syncAgentContext(recentBattle: battleSummary)
            } catch {
                self.isChallenging = false
                self.consoleLog.log("Challenge failed: \(error.localizedDescription)", level: .error, category: "Battle")
            }
        }
    }

    // MARK: - Agent

    func startAgent(pendingMessage: String? = nil) {
        agentSession.onReady = { [weak self] in
            guard let self else { return }
            self.syncAgentContext()
            if let pendingMessage {
                self.agentSession.sendMessage(pendingMessage)
            }
        }
        agentSession.onToolRequest = { [weak self] requestId, tool, arguments in
            self?.handleToolRequest(requestId: requestId, tool: tool, arguments: arguments)
        }
        agentSession.start()
    }

    func onWarriorCodeChanged() {
        syncAgentContext()
    }

    func syncAgentContext(recentBattle: String? = nil) {
        guard agentSession.isConnected else { return }
        agentSession.setContext(warriorCode: warriorCode, recentBattle: recentBattle)
    }

    // MARK: - Tool Request Handling

    private func handleToolRequest(requestId: String, tool: String, arguments: [String: AnyCodableValue]) {
        Task {
            do {
                let result: String
                switch tool {
                case "upload_warrior":
                    result = try await handleUploadWarrior(arguments: arguments)
                case "challenge_player":
                    result = try await handleChallenge(arguments: arguments)
                case "get_profile":
                    result = try await handleGetProfile()
                case "get_leaderboard":
                    result = try await handleGetLeaderboard()
                default:
                    agentSession.sendToolResponse(requestId: requestId, data: "Unknown tool: \(tool)", isError: true)
                    return
                }
                agentSession.sendToolResponse(requestId: requestId, data: result)
            } catch {
                agentSession.sendToolResponse(requestId: requestId, data: error.localizedDescription, isError: true)
            }
        }
    }

    private func handleUploadWarrior(arguments: [String: AnyCodableValue]) async throws -> String {
        let name = arguments["name"]?.stringValue ?? warriorName
        let redcode = arguments["redcode"]?.stringValue ?? warriorCode

        isUploading = true
        let warrior = try await apiClient.uploadWarrior(name: name, redcode: redcode)
        isUploading = false

        // Update local state
        self.warriorCode = redcode
        self.warriorName = name
        consoleLog.log("Warrior '\(warrior.name)' uploaded via agent (\(warrior.instructionCount ?? 0) instructions)", category: "API")
        fetchProfile()

        let response: [String: Any] = [
            "id": warrior.id,
            "name": warrior.name,
            "instruction_count": warrior.instructionCount ?? 0,
        ]
        return String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8) ?? "{}"
    }

    private func handleChallenge(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let defenderId = arguments["defender_id"]?.intValue else {
            throw APIError.invalidResponse
        }

        isChallenging = true
        let result = try await apiClient.challenge(defenderId: defenderId)
        isChallenging = false

        consoleLog.log("Challenge result via agent: \(result.result) (\(result.challengerWins)-\(result.defenderWins)-\(result.ties))", category: "Battle")
        fetchProfile()
        fetchLeaderboard()

        // Sync context with battle result
        let battleSummary = "Last battle: \(result.result) (\(result.challengerWins)W-\(result.defenderWins)L-\(result.ties)T)"
        syncAgentContext(recentBattle: battleSummary)

        var response: [String: Any] = [
            "battle_id": result.battleId,
            "result": result.result,
            "challenger_wins": result.challengerWins,
            "defender_wins": result.defenderWins,
            "ties": result.ties,
        ]
        if let ratingChanges = result.ratingChanges {
            response["rating_change"] = ratingChanges.challenger.change
            response["new_rating"] = ratingChanges.challenger.after
        }
        return String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8) ?? "{}"
    }

    private func handleGetProfile() async throws -> String {
        let profile = try await apiClient.fetchProfile()
        self.player = profile
        if let warrior = profile.warrior {
            self.warriorCode = warrior.redcode
            self.warriorName = warrior.name
        }
        consoleLog.log("Profile loaded via agent: \(profile.name) (rating: \(Int(profile.rating)))", category: "API")

        var response: [String: Any] = [
            "id": profile.id,
            "name": profile.name,
            "rating": profile.rating,
            "wins": profile.wins,
            "losses": profile.losses,
            "ties": profile.ties,
        ]
        if let warrior = profile.warrior {
            response["warrior"] = [
                "id": warrior.id,
                "name": warrior.name,
                "redcode": warrior.redcode,
            ]
        }
        return String(data: try JSONSerialization.data(withJSONObject: response), encoding: .utf8) ?? "{}"
    }

    private func handleGetLeaderboard() async throws -> String {
        let response = try await apiClient.fetchLeaderboard()
        self.leaderboard = response.leaderboard
        self.consoleLog.log("Leaderboard loaded via agent: \(response.totalPlayers) players", category: "API")

        let entries = response.leaderboard.map { entry -> [String: Any] in
            [
                "rank": entry.rank,
                "id": entry.id,
                "name": entry.name,
                "rating": entry.rating,
                "wins": entry.wins,
                "losses": entry.losses,
                "ties": entry.ties,
            ]
        }
        let result: [String: Any] = [
            "leaderboard": entries,
            "total_players": response.totalPlayers,
        ]
        return String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8) ?? "{}"
    }

    func shutdown() {
        agentSession.shutdown()
    }
}
