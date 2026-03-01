import Foundation

// MARK: - Request Types

struct ClaudeRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [ClaudeMessage]
    let tools: [AnyEncodable]?
    let stream: Bool
    let thinking: ClaudeThinking?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system, messages, tools, stream, thinking
    }
}

struct ClaudeThinking: Encodable {
    let type: String
    let budgetTokens: Int

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    static let enabled = ClaudeThinking(type: "enabled", budgetTokens: 10000)
}

struct ClaudeMessage: Codable {
    let role: String
    let content: ClaudeContent

    init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(role: String, blocks: [ClaudeContentBlock]) {
        self.role = role
        self.content = .blocks(blocks)
    }
}

enum ClaudeContent: Codable {
    case text(String)
    case blocks([ClaudeContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let str):
            try container.encode(str)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .text(str)
        } else if let blocks = try? container.decode([ClaudeContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .text("")
        }
    }
}

enum ClaudeContentBlock: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: AnyCodableValue])
    case toolResult(toolUseId: String, content: String, isError: Bool?)
    case thinking(thinking: String, signature: String)
    case serverToolUse(id: String, name: String, input: [String: AnyCodableValue])
    case webSearchResult(toolUseId: String, content: [WebSearchResultEntry])

    struct WebSearchResultEntry: Codable {
        let type: String
        let url: String?
        let title: String?
        let encryptedContent: String?
        let pageAge: String?

        enum CodingKeys: String, CodingKey {
            case type, url, title
            case encryptedContent = "encrypted_content"
            case pageAge = "page_age"
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
        case thinking, signature
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            if let isError { try container.encode(isError, forKey: .isError) }
        case .thinking(let thinking, let signature):
            try container.encode("thinking", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
            try container.encode(signature, forKey: .signature)
        case .serverToolUse(let id, let name, let input):
            try container.encode("server_tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .webSearchResult(let toolUseId, let content):
            try container.encode("web_search_tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = (try? container.decode([String: AnyCodableValue].self, forKey: .input)) ?? [:]
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = (try? container.decode(String.self, forKey: .content)) ?? ""
            let isError = try? container.decode(Bool.self, forKey: .isError)
            self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
        case "thinking":
            let thinking = try container.decode(String.self, forKey: .thinking)
            let signature = (try? container.decode(String.self, forKey: .signature)) ?? ""
            self = .thinking(thinking: thinking, signature: signature)
        case "server_tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = (try? container.decode([String: AnyCodableValue].self, forKey: .input)) ?? [:]
            self = .serverToolUse(id: id, name: name, input: input)
        case "web_search_tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = (try? container.decode([WebSearchResultEntry].self, forKey: .content)) ?? []
            self = .webSearchResult(toolUseId: toolUseId, content: content)
        default:
            self = .text("")
        }
    }
}

// MARK: - Tool Definitions

struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let inputSchema: [String: AnyEncodable]

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct ClaudeWebSearchTool: Encodable {
    let type = "web_search_20250305"
    let name = "web_search"
    let maxUses: Int

    enum CodingKeys: String, CodingKey {
        case type, name
        case maxUses = "max_uses"
    }
}

// MARK: - Response Types

struct ClaudeResponse: Decodable {
    let id: String
    let role: String
    let content: [ClaudeContentBlock]
    let stopReason: String?
    let usage: ClaudeUsage?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case stopReason = "stop_reason"
        case usage
    }
}

struct ClaudeUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Streaming Types

struct ClaudeStreamEvent {
    let type: ClaudeStreamEventType
    let data: Data
}

enum ClaudeStreamEventType: String {
    case messageStart = "message_start"
    case contentBlockStart = "content_block_start"
    case contentBlockDelta = "content_block_delta"
    case contentBlockStop = "content_block_stop"
    case messageDelta = "message_delta"
    case messageStop = "message_stop"
    case ping
    case error
}

// MARK: - AnyEncodable wrapper

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }

    init(_ dict: [String: Any]) {
        encodeClosure = { encoder in
            var container = encoder.singleValueContainer()
            let data = try JSONSerialization.data(withJSONObject: dict)
            let json = try JSONSerialization.jsonObject(with: data)
            try container.encode(JSONValue(json))
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

// Internal helper for encoding arbitrary JSON
private enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(_ value: Any) {
        switch value {
        case let s as String:
            self = .string(s)
        case let i as Int:
            self = .int(i)
        case let d as Double:
            self = .number(d)
        case let b as Bool:
            self = .bool(b)
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSONValue($0) })
        case let arr as [Any]:
            self = .array(arr.map { JSONValue($0) })
        default:
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        case .int(let i): try container.encode(i)
        case .bool(let b): try container.encode(b)
        case .object(let dict): try container.encode(dict)
        case .array(let arr): try container.encode(arr)
        case .null: try container.encodeNil()
        }
    }
}
