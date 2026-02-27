import Foundation

struct Battle: Codable, Identifiable {
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

struct ChallengeResponse: Codable {
    let battleId: Int
    let result: String
    let challengerWins: Int
    let defenderWins: Int
    let ties: Int
    let ratingChanges: RatingChanges?

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case result
        case challengerWins = "challenger_wins"
        case defenderWins = "defender_wins"
        case ties
        case ratingChanges = "rating_changes"
    }

    struct RatingChanges: Codable {
        let challenger: RatingChange
        let defender: RatingChange

        struct RatingChange: Codable {
            let before: Double
            let after: Double
        }
    }
}
