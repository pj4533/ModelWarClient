import Foundation

enum ChatMessageRole: Equatable {
    case thinking
    case assistant
    case toolUse(name: String)
    case toolResult(isError: Bool)
    case user
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(role: ChatMessageRole, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }
}
