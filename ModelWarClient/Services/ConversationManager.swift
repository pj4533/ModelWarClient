import Foundation
import OSLog

@MainActor
final class ConversationManager {
    private let claudeClient: ClaudeClient
    private let log = Logger(subsystem: "com.saygoodnight.ModelWarClient", category: "Conversation")

    var conversationHistory: [ClaudeMessage] = []
    var warriorContext: String = ""
    var recentBattle: String?
    var model: String = Constants.anthropicDefaultModel

    // Callbacks for UI updates
    var onStreamTextStart: (() -> Void)?
    var onStreamTextDelta: ((String) -> Void)?
    var onStreamThinkingStart: (() -> Void)?
    var onStreamThinkingDelta: ((String) -> Void)?
    var onStreamToolStart: ((String) -> Void)?
    var onContentBlockStop: (() -> Void)?
    var onToolUse: ((String, String) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onTurnEnded: (() -> Void)?
    var onError: ((String) -> Void)?

    /// Tool executor callback — called with (toolName, arguments) → result string
    var toolExecutor: ((String, [String: AnyCodableValue]) async throws -> String)?

    init(claudeClient: ClaudeClient) {
        self.claudeClient = claudeClient
    }

    func sendMessage(_ text: String) async {
        // Build the user message with context prepended
        var fullMessage = text
        var contextParts: [String] = []
        if !warriorContext.isEmpty {
            contextParts.append("[Context] Current warrior code in editor:\n```redcode\n\(warriorContext)\n```")
        }
        if let recentBattle, !recentBattle.isEmpty {
            contextParts.append("[Context] \(recentBattle)")
        }
        if !contextParts.isEmpty {
            fullMessage = contextParts.joined(separator: "\n") + "\n\nUser message: \(text)"
        }

        conversationHistory.append(ClaudeMessage(role: "user", content: fullMessage))

        // Agentic loop: keep calling API while there are tool calls
        await runAgenticLoop()
    }

    // MARK: - Agentic Loop

    private func runAgenticLoop() async {
        var continueLoop = true

        while continueLoop {
            continueLoop = false

            let request = ClaudeRequest(
                model: model,
                maxTokens: Constants.anthropicMaxTokens,
                system: SystemPrompt.text,
                messages: conversationHistory,
                tools: ToolDefinitions.allTools(),
                stream: true,
                thinking: ClaudeThinking.enabled
            )

            var assistantBlocks: [ClaudeContentBlock] = []
            var currentToolInputJSON = ""
            var currentToolId = ""
            var currentToolName = ""
            var currentBlockType = ""  // Track what kind of block we're in
            var currentTextAccumulator = ""  // Accumulate streamed text
            var currentThinkingAccumulator = ""  // Accumulate streamed thinking
            var currentThinkingSignature = ""  // Track thinking signature from block start
            var pendingToolUses: [(id: String, name: String, input: [String: AnyCodableValue])] = []
            var stopReason: String?

            do {
                let stream = claudeClient.streamMessage(request: request)

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event.type {
                    case .messageStart:
                        break

                    case .contentBlockStart:
                        if let parsed = decodeJSON(event.data) as? [String: Any],
                           let contentBlock = parsed["content_block"] as? [String: Any],
                           let cbType = contentBlock["type"] as? String {
                            currentBlockType = cbType
                            switch cbType {
                            case "text":
                                currentTextAccumulator = ""
                                onStreamTextStart?()
                            case "thinking":
                                currentThinkingAccumulator = ""
                                currentThinkingSignature = ""
                                onStreamThinkingStart?()
                            case "tool_use":
                                currentToolId = contentBlock["id"] as? String ?? ""
                                currentToolName = contentBlock["name"] as? String ?? ""
                                currentToolInputJSON = ""
                                onStreamToolStart?(currentToolName)
                            case "server_tool_use":
                                currentToolId = contentBlock["id"] as? String ?? ""
                                currentToolName = contentBlock["name"] as? String ?? ""
                                onStreamToolStart?(currentToolName)
                            default:
                                break
                            }
                        }

                    case .contentBlockDelta:
                        if let parsed = decodeJSON(event.data) as? [String: Any],
                           let delta = parsed["delta"] as? [String: Any],
                           let deltaType = delta["type"] as? String {
                            switch deltaType {
                            case "text_delta":
                                let text = delta["text"] as? String ?? ""
                                currentTextAccumulator += text
                                onStreamTextDelta?(text)
                            case "thinking_delta":
                                let thinking = delta["thinking"] as? String ?? ""
                                currentThinkingAccumulator += thinking
                                onStreamThinkingDelta?(thinking)
                            case "signature_delta":
                                let sig = delta["signature"] as? String ?? ""
                                currentThinkingSignature += sig
                            case "input_json_delta":
                                let partial = delta["partial_json"] as? String ?? ""
                                currentToolInputJSON += partial
                            default:
                                break
                            }
                        }

                    case .contentBlockStop:
                        // Finalize the current block and add to assistant history
                        switch currentBlockType {
                        case "text":
                            if !currentTextAccumulator.isEmpty {
                                assistantBlocks.append(.text(currentTextAccumulator))
                            }
                            currentTextAccumulator = ""
                        case "thinking":
                            if !currentThinkingAccumulator.isEmpty {
                                assistantBlocks.append(.thinking(
                                    thinking: currentThinkingAccumulator,
                                    signature: currentThinkingSignature
                                ))
                            }
                            currentThinkingAccumulator = ""
                            currentThinkingSignature = ""
                        case "tool_use":
                            if !currentToolId.isEmpty && !currentToolName.isEmpty {
                                let input = currentToolInputJSON.isEmpty ? [:] : parseToolInput(currentToolInputJSON)
                                pendingToolUses.append((id: currentToolId, name: currentToolName, input: input))
                                assistantBlocks.append(.toolUse(id: currentToolId, name: currentToolName, input: input))
                                onToolUse?(currentToolName, currentToolInputJSON)
                            }
                            currentToolId = ""
                            currentToolName = ""
                            currentToolInputJSON = ""
                        case "server_tool_use":
                            if !currentToolId.isEmpty && !currentToolName.isEmpty {
                                let input = currentToolInputJSON.isEmpty ? [:] : parseToolInput(currentToolInputJSON)
                                pendingToolUses.append((id: currentToolId, name: currentToolName, input: input))
                                assistantBlocks.append(.serverToolUse(id: currentToolId, name: currentToolName, input: input))
                                onToolUse?(currentToolName, currentToolInputJSON)
                            }
                            currentToolId = ""
                            currentToolName = ""
                            currentToolInputJSON = ""
                        default:
                            break
                        }
                        currentBlockType = ""
                        onContentBlockStop?()

                    case .messageDelta:
                        if let parsed = decodeJSON(event.data) as? [String: Any],
                           let delta = parsed["delta"] as? [String: Any] {
                            stopReason = delta["stop_reason"] as? String
                        }

                    case .messageStop:
                        break

                    case .ping:
                        break

                    case .error:
                        if let parsed = decodeJSON(event.data) as? [String: Any],
                           let error = parsed["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            onError?(message)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    log.error("Stream error: \(error.localizedDescription)")
                    onError?(error.localizedDescription)
                }
                onTurnEnded?()
                return
            }

            // Append assistant message to history (includes all blocks: thinking, text, tool_use)
            if !assistantBlocks.isEmpty {
                conversationHistory.append(ClaudeMessage(role: "assistant", blocks: assistantBlocks))
            }

            // Handle tool use
            if stopReason == "tool_use" && !pendingToolUses.isEmpty {
                var toolResults: [ClaudeContentBlock] = []

                for toolCall in pendingToolUses {
                    // Skip server-side tools (web search) — they're handled by the API
                    if toolCall.name == "web_search" {
                        continue
                    }

                    do {
                        guard let executor = toolExecutor else {
                            throw ClaudeClientError.noApiKey
                        }
                        let result = try await executor(toolCall.name, toolCall.input)
                        toolResults.append(.toolResult(toolUseId: toolCall.id, content: result, isError: nil))
                        onToolResult?(result, false)
                    } catch {
                        let errorMsg = error.localizedDescription
                        toolResults.append(.toolResult(toolUseId: toolCall.id, content: errorMsg, isError: true))
                        onToolResult?(errorMsg, true)
                    }
                }

                if !toolResults.isEmpty {
                    conversationHistory.append(ClaudeMessage(role: "user", blocks: toolResults))
                    continueLoop = true // Loop back for next API call
                }
            }
        }

        onTurnEnded?()
    }

    // MARK: - Helpers

    private func parseToolInput(_ json: String) -> [String: AnyCodableValue] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private nonisolated func decodeJSON(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }
}
