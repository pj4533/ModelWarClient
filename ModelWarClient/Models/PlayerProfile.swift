import Foundation

struct PlayerProfile: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let rating: Double
    let provisional: Bool
    let wins: Int
    let losses: Int
    let ties: Int
    let winRate: Double
    let ratingHistory: [Double]?
    let warrior: ProfileWarrior?
    let recentBattles: [RecentBattle]
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, rating, provisional, wins, losses, ties
        case winRate = "win_rate"
        case ratingHistory = "rating_history"
        case warrior
        case recentBattles = "recent_battles"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    struct ProfileWarrior: Codable, Sendable {
        let name: String
        let redcode: String
    }

    struct RecentBattle: Codable, Identifiable, Sendable {
        let id: Int
        let type: String
        let href: String
        let opponent: Opponent?
        let result: String
        let score: String
        let ratingChange: Double
        let createdAt: String
        // Arena-specific fields
        let placement: Int?
        let participantCount: Int?
        let matchup: String?

        enum CodingKeys: String, CodingKey {
            case id, type, href, opponent, result, score, placement, matchup
            case ratingChange = "rating_change"
            case createdAt = "created_at"
            case participantCount = "participant_count"
        }

        struct Opponent: Codable, Sendable {
            let id: Int
            let name: String
        }
    }
}
