import Foundation

struct Warrior: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let redcode: String?
    let instructionCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, redcode
        case instructionCount = "instruction_count"
    }
}
