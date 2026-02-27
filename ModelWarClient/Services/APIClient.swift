import Foundation
import OSLog

@MainActor
final class APIClient {
    private let baseURL = Constants.apiBaseURL
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ModelWarClient", category: "APIClient")
    private var apiKey: String?

    struct RegistrationResult {
        let id: Int
        let name: String
        let apiKey: String
    }

    func setApiKey(_ key: String?) {
        apiKey = key
    }

    // MARK: - Registration

    func register(name: String) async throws -> RegistrationResult {
        let body: [String: Any] = ["name": name]
        let rawData = try await postRawData(path: "/register", body: body, authenticated: false)
        guard let data = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              let id = data["id"] as? Int,
              let name = data["name"] as? String,
              let apiKey = data["api_key"] as? String else {
            throw APIError.invalidResponse
        }
        return RegistrationResult(id: id, name: name, apiKey: apiKey)
    }

    // MARK: - Profile

    func fetchProfile() async throws -> Player {
        let jsonData = try await getRawData(path: "/me")
        return try decode(Player.self, from: jsonData, context: "fetchProfile")
    }

    // MARK: - Warriors

    func uploadWarrior(name: String, redcode: String) async throws -> Warrior {
        let body: [String: Any] = ["name": name, "redcode": redcode]
        let jsonData = try await postRawData(path: "/warriors", body: body)
        return try decode(Warrior.self, from: jsonData, context: "uploadWarrior")
    }

    // MARK: - Challenge

    func challenge(defenderId: Int) async throws -> ChallengeResponse {
        let body: [String: Any] = ["defender_id": defenderId]
        let jsonData = try await postRawData(path: "/challenge", body: body)
        return try decode(ChallengeResponse.self, from: jsonData, context: "challenge")
    }

    // MARK: - Leaderboard

    func fetchLeaderboard() async throws -> LeaderboardResponse {
        let jsonData = try await getRawData(path: "/leaderboard", authenticated: false)
        return try decode(LeaderboardResponse.self, from: jsonData, context: "fetchLeaderboard")
    }

    // MARK: - Replay

    func fetchReplay(battleId: Int) async throws -> BattleReplay {
        let jsonData = try await getRawData(path: "/battles/\(battleId)/replay")
        return try decode(BattleReplay.self, from: jsonData, context: "fetchReplay")
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, context: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let rawJSON = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            log.error("Decode failed [\(context)] for \(String(describing: type)): \(error)\nRaw JSON: \(rawJSON)")
            throw error
        }
    }

    // MARK: - HTTP Helpers

    private func getRawData(path: String, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "GET"
        if authenticated {
            guard let apiKey else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func postRawData(path: String, body: [String: Any], authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let apiKey else { throw APIError.notAuthenticated }
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                throw APIError.serverError(httpResponse.statusCode, errorMessage)
            }
            throw APIError.serverError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }
    }
}

enum APIError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please set your API key."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}
