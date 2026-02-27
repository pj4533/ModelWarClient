import Foundation

struct LeaderboardEntry: Codable, Identifiable, Sendable {
    let rank: Int
    let id: Int
    let name: String
    let rating: Double
    let wins: Int
    let losses: Int
    let ties: Int
}

struct LeaderboardResponse: Codable, Sendable {
    let leaderboard: [LeaderboardEntry]
    let totalPlayers: Int

    enum CodingKeys: String, CodingKey {
        case leaderboard
        case totalPlayers = "total_players"
    }
}
