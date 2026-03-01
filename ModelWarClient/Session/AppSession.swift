import Foundation

@Observable
final class AppSession {
    var apiKey: String?
    var anthropicKey: String?
    var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
            agentSession?.setModel(selectedModel)
        }
    }
    var player: Player?
    var warriorCode: String = RedcodeTemplates.imp
    var warriorName: String = "MyWarrior"
    var showingSettings = false
    var leaderboard: [LeaderboardEntry] = []
    var leaderboardPage = 1
    var leaderboardHasMore = false
    var isLoadingMoreLeaderboard = false
    var isChallenging = false
    var isUploading = false
    var showingBattleResult = false
    var lastChallengeResult: ChallengeResponse?
    var challengeReplay: BattleReplay?
    var challengeDefenderName = ""
    var showingPlayerProfile = false
    var selectedPlayerProfile: PlayerProfile?
    var isLoadingPlayerProfile = false

    let consoleLog = ConsoleLog()
    let apiClient = APIClient()
    private(set) var agentSession: AgentSession!

    init() {
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? Constants.anthropicDefaultModel
        agentSession = AgentSession(consoleLog: consoleLog)
        loadApiKey()
        loadAnthropicKey()
        startAgent()
    }

    // MARK: - ModelWar API Key Management

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

    // MARK: - Anthropic API Key Management

    func loadAnthropicKey() {
        if let key = KeychainService.load(
            service: Constants.anthropicKeychainService,
            account: Constants.anthropicKeychainAccount
        ) {
            anthropicKey = key
            agentSession.claudeClient.setApiKey(key)
            consoleLog.log("Anthropic API key loaded from Keychain", category: "Auth")
        }
    }

    func setAnthropicKey(_ key: String) {
        anthropicKey = key
        _ = KeychainService.save(
            apiKey: key,
            service: Constants.anthropicKeychainService,
            account: Constants.anthropicKeychainAccount
        )
        agentSession.claudeClient.setApiKey(key)
        consoleLog.log("Anthropic API key saved", category: "Auth")

        // Start agent if not already connected
        if !agentSession.isConnected {
            startAgent()
        }
    }

    func clearAnthropicKey() {
        anthropicKey = nil
        agentSession.claudeClient.setApiKey(nil)
        KeychainService.delete(
            service: Constants.anthropicKeychainService,
            account: Constants.anthropicKeychainAccount
        )
        agentSession.shutdown()
        consoleLog.log("Anthropic API key cleared", category: "Auth")
    }

    func logout() {
        agentSession.shutdown()
        agentSession.messages.removeAll()
        clearApiKey()
        clearAnthropicKey()
        leaderboard = []
        leaderboardPage = 1
        leaderboardHasMore = false
        warriorCode = RedcodeTemplates.imp
        warriorName = "MyWarrior"
        consoleLog.log("Logged out — all state reset", category: "Auth")
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
                let response = try await apiClient.fetchLeaderboard(page: 1)
                self.leaderboard = response.leaderboard
                self.leaderboardPage = 1
                self.leaderboardHasMore = response.pagination.page < response.pagination.totalPages
                self.consoleLog.log("Leaderboard loaded: \(response.totalPlayers) players, entries=\(response.leaderboard.count), page=\(response.pagination.page)/\(response.pagination.totalPages), hasMore=\(self.leaderboardHasMore)", category: "API")
            } catch {
                consoleLog.log("Failed to load leaderboard: \(error.localizedDescription)", level: .error, category: "API")
            }
        }
    }

    func loadMoreLeaderboard() {
        consoleLog.log("loadMoreLeaderboard called: hasMore=\(leaderboardHasMore), isLoading=\(isLoadingMoreLeaderboard), currentPage=\(leaderboardPage), entries=\(leaderboard.count)", category: "Leaderboard")
        guard leaderboardHasMore, !isLoadingMoreLeaderboard else {
            consoleLog.log("loadMoreLeaderboard: bailing out (hasMore=\(leaderboardHasMore), isLoading=\(isLoadingMoreLeaderboard))", level: .debug, category: "Leaderboard")
            return
        }
        isLoadingMoreLeaderboard = true
        let nextPage = leaderboardPage + 1

        Task {
            do {
                let response = try await apiClient.fetchLeaderboard(page: nextPage)
                self.leaderboard.append(contentsOf: response.leaderboard)
                self.leaderboardPage = nextPage
                self.leaderboardHasMore = response.pagination.page < response.pagination.totalPages
                self.isLoadingMoreLeaderboard = false
                self.consoleLog.log("Leaderboard page \(nextPage) loaded: \(response.leaderboard.count) new, \(self.leaderboard.count) total, page=\(response.pagination.page)/\(response.pagination.totalPages), hasMore=\(self.leaderboardHasMore)", category: "API")
            } catch {
                self.isLoadingMoreLeaderboard = false
                consoleLog.log("Failed to load more leaderboard: \(error.localizedDescription)", level: .error, category: "API")
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

    func challenge(defenderId: Int, defenderName: String = "") {
        isChallenging = true
        challengeDefenderName = defenderName
        lastChallengeResult = nil
        challengeReplay = nil
        showingBattleResult = true

        Task {
            do {
                let result = try await apiClient.challenge(defenderId: defenderId)
                self.isChallenging = false
                self.lastChallengeResult = result
                self.consoleLog.log("Challenge result: \(result.result) (\(result.challengerWins)-\(result.defenderWins)-\(result.ties))", category: "Battle")
                self.fetchProfile()
                self.fetchLeaderboard()

                let battleSummary = "Last battle: \(result.result) (\(result.challengerWins)W-\(result.defenderWins)L-\(result.ties)T)"
                self.syncAgentContext(recentBattle: battleSummary)

                do {
                    let replay = try await apiClient.fetchReplay(battleId: result.battleId)
                    self.challengeReplay = replay
                } catch {
                    self.consoleLog.log("Failed to load replay: \(error.localizedDescription)", level: .error, category: "Battle")
                }
            } catch {
                self.isChallenging = false
                self.showingBattleResult = false
                self.consoleLog.log("Challenge failed: \(error.localizedDescription)", level: .error, category: "Battle")
            }
        }
    }

    func dismissBattleResult() {
        showingBattleResult = false
        lastChallengeResult = nil
        challengeReplay = nil
        challengeDefenderName = ""
    }

    // MARK: - Player Profile

    func fetchPlayerProfile(id: Int) {
        selectedPlayerProfile = nil
        isLoadingPlayerProfile = true
        showingPlayerProfile = true

        Task {
            do {
                let profile = try await apiClient.fetchPlayerProfile(id: id)
                self.selectedPlayerProfile = profile
                self.isLoadingPlayerProfile = false
                self.consoleLog.log("Player profile loaded: \(profile.name)", category: "API")
            } catch {
                self.isLoadingPlayerProfile = false
                self.showingPlayerProfile = false
                self.consoleLog.log("Failed to load player profile: \(error.localizedDescription)", level: .error, category: "API")
            }
        }
    }

    func dismissPlayerProfile() {
        showingPlayerProfile = false
        selectedPlayerProfile = nil
        isLoadingPlayerProfile = false
    }

    // MARK: - Agent

    func startAgent(pendingMessage: String? = nil) {
        guard anthropicKey != nil else {
            consoleLog.log("No Anthropic API key — agent not started", level: .debug, category: "Agent")
            if let pendingMessage {
                // Queue the message; it'll be sent once key is set and agent starts
                consoleLog.log("Pending message queued: \(pendingMessage.prefix(60))", level: .debug, category: "Agent")
            }
            return
        }

        agentSession.toolExecutor = { [weak self] name, arguments in
            guard let self else { throw APIError.notAuthenticated }
            return try await self.handleTool(name: name, arguments: arguments)
        }
        agentSession.setModel(selectedModel)
        agentSession.start()
        syncAgentContext()

        if let pendingMessage {
            agentSession.sendMessage(pendingMessage)
        }
    }

    func onWarriorCodeChanged() {
        syncAgentContext()
    }

    func syncAgentContext(recentBattle: String? = nil) {
        guard agentSession.isConnected else { return }
        agentSession.setContext(warriorCode: warriorCode, recentBattle: recentBattle)
    }

    // MARK: - Tool Handling

    private func handleTool(name: String, arguments: [String: AnyCodableValue]) async throws -> String {
        switch name {
        case "upload_warrior":
            return try await handleUploadWarrior(arguments: arguments)
        case "challenge_player":
            return try await handleChallenge(arguments: arguments)
        case "get_profile":
            return try await handleGetProfile()
        case "get_leaderboard":
            return try await handleGetLeaderboard()
        case "get_player_profile":
            return try await handleGetPlayerProfile(arguments: arguments)
        case "get_battle":
            return try await handleGetBattle(arguments: arguments)
        case "get_battle_replay":
            return try await handleGetBattleReplay(arguments: arguments)
        case "get_battles":
            return try await handleGetBattles(arguments: arguments)
        case "get_player_battles":
            return try await handleGetPlayerBattles(arguments: arguments)
        case "get_warrior":
            return try await handleGetWarrior(arguments: arguments)
        case "upload_arena_warrior":
            return try await handleUploadArenaWarrior(arguments: arguments)
        case "start_arena":
            return try await handleStartArena()
        case "get_arena_leaderboard":
            return try await handleGetArenaLeaderboard()
        case "get_arena":
            return try await handleGetArena(arguments: arguments)
        case "get_arena_replay":
            return try await handleGetArenaReplay(arguments: arguments)
        default:
            throw APIError.invalidResponse
        }
    }

    private func handleUploadWarrior(arguments: [String: AnyCodableValue]) async throws -> String {
        let name = arguments["name"]?.stringValue ?? warriorName
        let redcode = arguments["redcode"]?.stringValue ?? warriorCode

        isUploading = true
        let warrior = try await apiClient.uploadWarrior(name: name, redcode: redcode)
        isUploading = false

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

    private func handleGetPlayerProfile(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let playerId = arguments["player_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let profile = try await apiClient.fetchPlayerProfile(id: playerId)
        consoleLog.log("Player profile loaded via agent: \(profile.name)", category: "API")
        return String(data: try JSONEncoder().encode(profile), encoding: .utf8) ?? "{}"
    }

    private func handleGetBattle(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let battleId = arguments["battle_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let data = try await apiClient.fetchBattle(id: battleId)
        consoleLog.log("Battle \(battleId) loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetBattleReplay(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let battleId = arguments["battle_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let data = try await apiClient.fetchReplay(battleId: battleId)
        consoleLog.log("Battle replay \(battleId) loaded via agent", category: "API")
        return String(data: try JSONEncoder().encode(data), encoding: .utf8) ?? "{}"
    }

    private func handleGetBattles(arguments: [String: AnyCodableValue]) async throws -> String {
        let page = arguments["page"]?.intValue ?? 1
        let perPage = arguments["per_page"]?.intValue ?? 20
        let data = try await apiClient.fetchBattles(page: page, perPage: perPage)
        consoleLog.log("Battle history loaded via agent (page \(page))", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetPlayerBattles(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let playerId = arguments["player_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let page = arguments["page"]?.intValue ?? 1
        let perPage = arguments["per_page"]?.intValue ?? 20
        let data = try await apiClient.fetchPlayerBattles(playerId: playerId, page: page, perPage: perPage)
        consoleLog.log("Player \(playerId) battles loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetWarrior(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let warriorId = arguments["warrior_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let data = try await apiClient.fetchWarrior(id: warriorId)
        consoleLog.log("Warrior \(warriorId) loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleUploadArenaWarrior(arguments: [String: AnyCodableValue]) async throws -> String {
        let name = arguments["name"]?.stringValue ?? "ArenaWarrior"
        let redcode = arguments["redcode"]?.stringValue ?? ""
        let autoJoin: Bool
        if case .bool(let b) = arguments["auto_join"] {
            autoJoin = b
        } else {
            autoJoin = true
        }
        let data = try await apiClient.uploadArenaWarrior(name: name, redcode: redcode, autoJoin: autoJoin)
        consoleLog.log("Arena warrior '\(name)' uploaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleStartArena() async throws -> String {
        let data = try await apiClient.startArena()
        consoleLog.log("Arena started via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetArenaLeaderboard() async throws -> String {
        let data = try await apiClient.fetchArenaLeaderboard()
        consoleLog.log("Arena leaderboard loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetArena(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let arenaId = arguments["arena_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let data = try await apiClient.fetchArena(id: arenaId)
        consoleLog.log("Arena \(arenaId) loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetArenaReplay(arguments: [String: AnyCodableValue]) async throws -> String {
        guard let arenaId = arguments["arena_id"]?.intValue else {
            throw APIError.invalidResponse
        }
        let data = try await apiClient.fetchArenaReplay(id: arenaId)
        consoleLog.log("Arena replay \(arenaId) loaded via agent", category: "API")
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func shutdown() {
        agentSession.shutdown()
    }
}
