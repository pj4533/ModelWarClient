import Foundation

struct BattleReplay: Codable, Sendable {
    let battleId: Int
    let challenger: ReplayWarrior
    let defender: ReplayWarrior
    let roundResults: [RoundResult]
    let settings: BattleSettings

    enum CodingKeys: String, CodingKey {
        case battleId = "battle_id"
        case challenger, defender
        case roundResults = "round_results"
        case settings
    }

    struct ReplayWarrior: Codable, Sendable {
        let name: String
        let redcode: String
    }

    struct RoundResult: Codable, Sendable {
        let round: Int
        let winner: String
        let seed: Int
    }

    struct BattleSettings: Codable, Sendable {
        let coreSize: Int
        let maxCycles: Int
        let maxLength: Int
        let maxTasks: Int
        let minSeparation: Int
    }
}
