import Foundation

struct Player: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let rating: Double
    let wins: Int
    let losses: Int
    let ties: Int
    var warrior: PlayerWarrior?

    struct PlayerWarrior: Codable, Sendable {
        let id: Int
        let name: String
        let redcode: String
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, name, redcode
            case updatedAt = "updated_at"
        }
    }
}
