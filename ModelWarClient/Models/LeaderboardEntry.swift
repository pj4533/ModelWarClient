import Foundation

struct LeaderboardEntry: Codable, Identifiable, Sendable {
    let rank: Int
    let id: Int
    let name: String
    let rating: Double
    let ratingDeviation: Double
    let wins: Int
    let losses: Int
    let ties: Int

    enum CodingKeys: String, CodingKey {
        case rank, id, name, rating
        case ratingDeviation = "rating_deviation"
        case wins, losses, ties
    }
}

struct LeaderboardPagination: Codable, Sendable {
    let page: Int
    let perPage: Int
    let total: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case total
        case totalPages = "total_pages"
    }
}

struct LeaderboardResponse: Codable, Sendable {
    let leaderboard: [LeaderboardEntry]
    let totalPlayers: Int
    let pagination: LeaderboardPagination

    enum CodingKeys: String, CodingKey {
        case leaderboard
        case totalPlayers = "total_players"
        case pagination
    }
}
