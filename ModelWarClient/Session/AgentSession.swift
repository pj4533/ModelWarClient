import Foundation

@Observable
final class AgentSession {
    var messages: [ChatMessage] = []
    var isConnected = false

    private let bridge = AgentBridge()
    private let consoleLog: ConsoleLog

    init(consoleLog: ConsoleLog) {
        self.consoleLog = consoleLog
        bridge.onMessage = { [weak self] message in
            self?.handleMessage(message)
        }
    }

    func start() {
        consoleLog.log("Starting agent bridge", category: "Agent")
        bridge.start()
        bridge.sendCommand(.startSession)
    }

    func sendMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, content: text))
        bridge.sendCommand(.userMessage(text: text))
        consoleLog.log("User message sent", level: .debug, category: "Agent")
    }

    func setContext(apiKey: String, warriorCode: String, recentBattle: String? = nil) {
        bridge.sendCommand(.setContext(apiKey: apiKey, warriorCode: warriorCode, recentBattle: recentBattle))
        consoleLog.log("Context updated for agent", level: .debug, category: "Agent")
    }

    func shutdown() {
        consoleLog.log("Shutting down agent bridge", category: "Agent")
        bridge.shutdown()
        isConnected = false
    }

    private func handleMessage(_ message: BridgeMessage) {
        switch message {
        case .sessionReady:
            isConnected = true
            consoleLog.log("Agent session ready", category: "Agent")

        case .agentText(let content):
            if let last = messages.last, last.role == .assistant, last.isStreaming {
                messages[messages.count - 1].content += content
            } else {
                finalizeStreamingMessage()
                messages.append(ChatMessage(role: .assistant, content: content, isStreaming: true))
            }

        case .agentThinking(let content):
            finalizeStreamingMessage()
            messages.append(ChatMessage(role: .thinking, content: content))

        case .agentToolUse(let name, let input):
            finalizeStreamingMessage()
            messages.append(ChatMessage(role: .toolUse(name: name), content: input))
            consoleLog.log("Tool use: \(name)", level: .debug, category: "Agent")

        case .agentToolResult(let content, let isError):
            messages.append(ChatMessage(role: .toolResult(isError: isError), content: content))
            if isError {
                consoleLog.log("Tool error: \(content.prefix(100))", level: .warning, category: "Agent")
            }

        case .turnEnded:
            finalizeStreamingMessage()
            consoleLog.log("Agent turn ended", level: .debug, category: "Agent")

        case .error(let msg):
            finalizeStreamingMessage()
            messages.append(ChatMessage(role: .assistant, content: "Error: \(msg)"))
            consoleLog.log("Agent error: \(msg)", level: .error, category: "Agent")
        }
    }

    private func finalizeStreamingMessage() {
        if let last = messages.last, last.isStreaming {
            messages[messages.count - 1].isStreaming = false
        }
    }
}
