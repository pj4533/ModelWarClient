import Foundation

enum ChatMessageRole: Equatable {
    case thinking
    case assistant
    case toolUse(name: String)
    case toolResult(name: String, isError: Bool)
    case user
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    /// Pre-parsed JSON for tool use/result messages.
    /// Parsed once at init to avoid repeated JSONSerialization on every view render.
    /// Excluded from Equatable conformance since it's derived from content.
    var parsedJSON: [String: Any]?

    init(role: ChatMessageRole, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming

        // Pre-parse JSON for tool messages (their content doesn't change after init)
        switch role {
        case .toolUse, .toolResult:
            if let data = content.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.parsedJSON = obj
            } else {
                self.parsedJSON = nil
            }
        default:
            self.parsedJSON = nil
        }
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.content == rhs.content
            && lhs.timestamp == rhs.timestamp
            && lhs.isStreaming == rhs.isStreaming
    }
}
