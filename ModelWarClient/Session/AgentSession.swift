import Foundation

@Observable
final class AgentSession {
    var messages: [ChatMessage] = []
    var isConnected = false
    var isProcessing = false

    /// Tool executor callback — AppSession sets this. Called with (toolName, arguments) → result string.
    @ObservationIgnored
    var toolExecutor: ((String, [String: AnyCodableValue]) async throws -> String)?

    let claudeClient = ClaudeClient()
    private var conversationManager: ConversationManager?
    private let consoleLog: ConsoleLog
    private var streamingTask: Task<Void, Never>?

    init(consoleLog: ConsoleLog) {
        self.consoleLog = consoleLog
    }

    func start() {
        guard claudeClient.hasApiKey else {
            consoleLog.log("No Anthropic API key — agent not started", level: .debug, category: "Agent")
            return
        }

        let manager = ConversationManager(claudeClient: claudeClient)
        manager.toolExecutor = { [weak self] name, arguments in
            guard let executor = self?.toolExecutor else {
                throw ClaudeClientError.noApiKey
            }
            return try await executor(name, arguments)
        }

        // Wire up UI callbacks
        manager.onStreamTextStart = { [weak self] in
            self?.finalizeStreamingMessage()
            self?.messages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))
        }

        manager.onStreamTextDelta = { [weak self] text in
            guard let self else { return }
            if let lastIndex = messages.indices.last,
               messages[lastIndex].role == .assistant,
               messages[lastIndex].isStreaming {
                messages[lastIndex].content += text
            }
        }

        manager.onStreamThinkingStart = { [weak self] in
            self?.finalizeStreamingMessage()
            self?.messages.append(ChatMessage(role: .thinking, content: "", isStreaming: true))
        }

        manager.onStreamThinkingDelta = { [weak self] text in
            guard let self else { return }
            if let lastIndex = messages.indices.last,
               messages[lastIndex].role == .thinking,
               messages[lastIndex].isStreaming {
                messages[lastIndex].content += text
            }
        }

        manager.onStreamToolStart = { [weak self] name in
            self?.finalizeStreamingMessage()
            self?.consoleLog.log("Tool use: \(name)", level: .debug, category: "Agent")
        }

        manager.onContentBlockStop = { [weak self] in
            self?.finalizeStreamingMessage()
        }

        manager.onToolUse = { [weak self] name, input in
            self?.finalizeStreamingMessage()
            self?.messages.append(ChatMessage(role: .toolUse(name: name), content: input))
            self?.consoleLog.log("Tool use: \(name)", level: .debug, category: "Agent")
        }

        manager.onToolResult = { [weak self] content, isError in
            self?.messages.append(ChatMessage(role: .toolResult(isError: isError), content: content))
            if isError {
                self?.consoleLog.log("Tool error: \(content.prefix(100))", level: .warning, category: "Agent")
            }
        }

        manager.onTurnEnded = { [weak self] in
            guard let self else { return }
            finalizeStreamingMessage()
            isProcessing = false
            if let last = messages.last, last.role == .assistant {
                consoleLog.log("Agent: \(last.content)", category: "Chat")
            }
            consoleLog.log("Agent turn ended", level: .debug, category: "Agent")
        }

        manager.onError = { [weak self] message in
            guard let self else { return }
            isProcessing = false
            finalizeStreamingMessage()
            messages.append(ChatMessage(role: .assistant, content: "Error: \(message)"))
            consoleLog.log("Agent error: \(message)", level: .error, category: "Agent")
        }

        self.conversationManager = manager
        isConnected = true
        consoleLog.log("Agent session ready (direct API)", category: "Agent")
    }

    func sendMessage(_ text: String) {
        guard let conversationManager else {
            consoleLog.log("Cannot send — no active session", level: .error, category: "Agent")
            return
        }

        isProcessing = true
        messages.append(ChatMessage(role: .user, content: text))
        consoleLog.log("User: \(text)", category: "Chat")

        streamingTask = Task {
            await conversationManager.sendMessage(text)
        }
    }

    func setContext(warriorCode: String, recentBattle: String? = nil) {
        conversationManager?.warriorContext = warriorCode
        conversationManager?.recentBattle = recentBattle
        consoleLog.log("Context updated for agent", level: .debug, category: "Agent")
    }

    func setModel(_ model: String) {
        conversationManager?.model = model
    }

    func shutdown() {
        consoleLog.log("Shutting down agent session", category: "Agent")
        streamingTask?.cancel()
        streamingTask = nil
        conversationManager = nil
        isConnected = false
    }

    private func finalizeStreamingMessage() {
        if let last = messages.last, last.isStreaming {
            messages[messages.count - 1].isStreaming = false
        }
    }
}
