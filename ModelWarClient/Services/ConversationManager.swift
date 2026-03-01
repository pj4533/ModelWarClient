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
    var onToolResult: ((String, String, Bool) -> Void)?  // (toolName, content, isError)
    var onTurnEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    /// Diagnostic log callback — surfaces internal logs to the app console
    var onDiagnosticLog: ((String) -> Void)?

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

        diagLog("Sending message (\(fullMessage.count) chars), history: \(conversationHistory.count) messages")
        conversationHistory.append(ClaudeMessage(role: "user", content: fullMessage))

        // Agentic loop: keep calling API while there are tool calls
        await runAgenticLoop()
    }

    /// Patch conversation history if the last assistant message has tool_use blocks
    /// without corresponding tool_result blocks (e.g., user interrupted mid-tool-execution).
    func patchIncompleteToolCalls() {
        guard let lastAssistantIndex = conversationHistory.lastIndex(where: { $0.role == "assistant" }) else { return }

        let assistantMessage = conversationHistory[lastAssistantIndex]
        guard case .blocks(let blocks) = assistantMessage.content else { return }

        // Collect tool_use IDs from the assistant message
        let toolUseIds: [String] = blocks.compactMap { block in
            switch block {
            case .toolUse(let id, _, _): return id
            case .serverToolUse(let id, _, _): return id
            default: return nil
            }
        }
        guard !toolUseIds.isEmpty else { return }

        // Check if there's already a user message with tool results after the assistant
        let nextIndex = lastAssistantIndex + 1
        if nextIndex < conversationHistory.count {
            let nextMessage = conversationHistory[nextIndex]
            if nextMessage.role == "user", case .blocks(let resultBlocks) = nextMessage.content {
                let existingResultIds = Set(resultBlocks.compactMap { block -> String? in
                    if case .toolResult(let toolUseId, _, _) = block { return toolUseId }
                    return nil
                })
                let missingIds = toolUseIds.filter { !existingResultIds.contains($0) }
                if missingIds.isEmpty { return } // All tool calls have results

                // Add missing results to the existing tool results message
                var updatedBlocks = resultBlocks
                for id in missingIds {
                    updatedBlocks.append(.toolResult(toolUseId: id, content: "Cancelled by user", isError: true))
                }
                conversationHistory[nextIndex] = ClaudeMessage(role: "user", blocks: updatedBlocks)
                diagLog("Patched \(missingIds.count) missing tool results (appended to existing)")
                return
            }
        }

        // No tool results message exists — add one with all results marked cancelled
        let cancelledResults = toolUseIds.map { id in
            ClaudeContentBlock.toolResult(toolUseId: id, content: "Cancelled by user", isError: true)
        }
        conversationHistory.append(ClaudeMessage(role: "user", blocks: cancelledResults))
        diagLog("Patched \(toolUseIds.count) missing tool results (new message)")
    }

    // MARK: - Agentic Loop

    private func runAgenticLoop() async {
        var continueLoop = true
        var loopIteration = 0

        while continueLoop {
            continueLoop = false
            loopIteration += 1

            diagLog("API call #\(loopIteration): model=\(model) history=\(conversationHistory.count) messages")

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
            var currentWebSearchResults: [ClaudeContentBlock.WebSearchResultEntry] = []
            var pendingToolUses: [(id: String, name: String, input: [String: AnyCodableValue])] = []
            var stopReason: String?
            var eventCount = 0

            do {
                let stream = claudeClient.streamMessage(request: request)
                diagLog("Stream created, awaiting events...")

                for try await event in stream {
                    eventCount += 1
                    if Task.isCancelled {
                        diagWarning("Task cancelled during stream after \(eventCount) events")
                        break
                    }

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
                            case "web_search_tool_result":
                                currentToolId = contentBlock["tool_use_id"] as? String ?? ""
                                currentWebSearchResults = []
                                if let contentArray = contentBlock["content"] as? [[String: Any]] {
                                    currentWebSearchResults = contentArray.compactMap { entry in
                                        ClaudeContentBlock.WebSearchResultEntry(
                                            type: entry["type"] as? String ?? "",
                                            url: entry["url"] as? String,
                                            title: entry["title"] as? String,
                                            encryptedContent: entry["encrypted_content"] as? String,
                                            pageAge: entry["page_age"] as? String
                                        )
                                    }
                                }
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
                        case "web_search_tool_result":
                            if !currentToolId.isEmpty {
                                assistantBlocks.append(.webSearchResult(
                                    toolUseId: currentToolId,
                                    content: currentWebSearchResults
                                ))
                                diagLog("Web search result captured (\(currentWebSearchResults.count) entries)")
                            }
                            currentToolId = ""
                            currentWebSearchResults = []
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
                    diagError("Stream error after \(eventCount) events: \(error.localizedDescription)")
                    onError?(error.localizedDescription)
                } else {
                    diagLog("Stream cancelled after \(eventCount) events")
                }
                onTurnEnded?()
                return
            }

            diagLog("Stream done: \(eventCount) events, \(assistantBlocks.count) blocks, stop=\(stopReason ?? "nil")")

            // Append assistant message to history (includes all blocks: thinking, text, tool_use)
            if !assistantBlocks.isEmpty {
                conversationHistory.append(ClaudeMessage(role: "assistant", blocks: assistantBlocks))
            } else {
                diagWarning("No content blocks received from API — assistant produced no output")
            }

            // Handle tool use
            if stopReason == "tool_use" && !pendingToolUses.isEmpty {
                var toolResults: [ClaudeContentBlock] = []

                diagLog("Processing \(pendingToolUses.count) tool calls")
                for toolCall in pendingToolUses {
                    // Skip server-side tools (web search) — they're handled by the API
                    if toolCall.name == "web_search" {
                        diagLog("Skipping server-side tool: \(toolCall.name)")
                        continue
                    }

                    diagLog("Executing tool: \(toolCall.name)")
                    do {
                        guard let executor = toolExecutor else {
                            diagError("No tool executor available")
                            throw ClaudeClientError.noApiKey
                        }
                        let result = try await executor(toolCall.name, toolCall.input)
                        diagLog("Tool \(toolCall.name) succeeded (\(result.count) chars)")
                        toolResults.append(.toolResult(toolUseId: toolCall.id, content: result, isError: nil))
                        onToolResult?(toolCall.name, result, false)
                    } catch {
                        let errorMsg = error.localizedDescription
                        diagError("Tool \(toolCall.name) failed: \(errorMsg)")
                        toolResults.append(.toolResult(toolUseId: toolCall.id, content: errorMsg, isError: true))
                        onToolResult?(toolCall.name, errorMsg, true)
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

    private func diagLog(_ message: String) {
        log.info("\(message)")
        onDiagnosticLog?(message)
    }

    private func diagWarning(_ message: String) {
        log.warning("\(message)")
        onDiagnosticLog?("⚠ \(message)")
    }

    private func diagError(_ message: String) {
        log.error("\(message)")
        onDiagnosticLog?("✖ \(message)")
    }

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
