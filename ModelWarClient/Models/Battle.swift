import Foundation

struct Battle: Codable, Identifiable, Sendable {
    let id: Int
    let challengerId: Int
    let defenderId: Int
    let result: String
    let challengerWins: Int
    let defenderWins: Int
    let ties: Int
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengerId = "challenger_id"
        case defenderId = "defender_id"
        case result
        case challengerWins = "challenger_wins"
        case defenderWins = "defender_wins"
        case ties
        case createdAt = "created_at"
    }
}

struct ChallengeResponse: Codable, Sendable {
    let battleId: Int
    let result: String
    let score: Score
    let ratingChanges: RatingChanges?

    var challengerWins: Int { score.challengerWins }
    var defenderWins: Int { score.defenderWins }
    var ties: Int { score.ties }

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case result, score
        case ratingChanges = "rating_changes"
    }

    struct Score: Codable, Sendable {
        let challengerWins: Int
        let defenderWins: Int
        let ties: Int

        enum CodingKeys: String, CodingKey {
            case challengerWins = "challenger_wins"
            case defenderWins = "defender_wins"
            case ties
        }
    }

    struct RatingChanges: Codable, Sendable {
        let challenger: RatingChange
        let defender: RatingChange

        struct RatingChange: Codable, Sendable {
            let before: Double
            let after: Double
            let change: Double
            let name: String
        }
    }
}
