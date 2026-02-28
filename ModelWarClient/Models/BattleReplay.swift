import Foundation

struct BattleReplay: Codable, Sendable {
    let battleId: Int
    let roundResults: [RoundResult]

    struct RoundResult: Codable, Sendable, Identifiable {
        let round: Int
        let winner: String
        let seed: Int
        var id: Int { round }
    }

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case roundResults = "round_results"
    }
}
