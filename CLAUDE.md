# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
xcodebuild -project ModelWarClient.xcodeproj -scheme ModelWarClient -destination 'platform=macOS' build
```

This is a **macOS-only** SwiftUI app (no iOS target). Always include `-destination 'platform=macOS'`.

## Project Overview

macOS SwiftUI IDE client for [modelwar.ai](https://www.modelwar.ai) — a Core War programming game. Four-panel layout: Code Editor + Chat (left), Leaderboard + Console (right). Users write Redcode warriors, chat with a Claude-powered agent, and battle other players.

## Architecture

### Observable State Pattern
- **AppSession** (`Session/AppSession.swift`): Central `@Observable` coordinator — API keys (ModelWar + Anthropic), player profile, warrior code, leaderboard, tool handling. This is the heart of the app.
- **AgentSession** (`Session/AgentSession.swift`): Manages ConversationManager lifecycle, chat message array, streaming state.
- **ConsoleLog** (`Session/ConsoleLog.swift`): Observable log collector with levels and categories.

### Claude API Integration (Direct HTTPS)
The app makes direct HTTPS calls to the Anthropic Messages API — no Python subprocess or bridge needed:
- **ClaudeClient** (`Services/ClaudeClient.swift`): HTTP client with SSE streaming parser. Uses `URLSession.AsyncBytes` for server-sent events. Extracts event type from the JSON payload `type` field rather than relying on empty-line boundaries (since `bytes.lines` strips empty lines). Includes diagnostic logging via `onDiagnosticLog` callback.
- **ConversationManager** (`Services/ConversationManager.swift`): Agentic tool loop. Manages conversation history, streams responses, and executes tool calls inline via async/await. Handles `server_tool_use` and `web_search_tool_result` content blocks for Anthropic's built-in web search. Patches incomplete tool calls on user interruption (only for client-side `toolUse` blocks, not server-side `serverToolUse` blocks). Includes diagnostic logging throughout.
- **ToolDefinitions** (`Services/ToolDefinitions.swift`): All 18 ModelWar tool schemas + built-in web search tool.
- **SystemPrompt** (`Services/SystemPrompt.swift`): Dynamic system prompt that instructs Claude to call `get_skill` on startup to fetch the latest Core War rules and reference material from modelwar.ai, rather than hardcoding game rules.

### Tool Execution Cycle
1. ConversationManager streams API response, accumulates `tool_use`, `server_tool_use`, and `web_search_tool_result` content blocks
2. On `stop_reason == "tool_use"`, executes each client-side tool via `toolExecutor` callback (skips server-side `web_search` tool)
3. `AppSession.handleTool()` dispatches to the appropriate API call and returns result
4. ConversationManager appends tool results to history and loops back to API
5. If the user interrupts mid-tool-execution, `patchIncompleteToolCalls()` adds "Cancelled by user" results for any unanswered client-side tool_use blocks (server-side `serverToolUse` blocks are excluded from patching)

Tools (18): `upload_warrior`, `challenge_player`, `get_profile`, `get_leaderboard`, `get_player_profile`, `get_battle`, `get_battle_replay`, `get_battles`, `get_player_battles`, `get_warrior`, `upload_arena_warrior`, `start_arena`, `get_arena_leaderboard`, `get_arena`, `get_arena_replay`, `get_skill`, `get_theory`

- `get_skill` fetches `modelwar.ai/skill.md` — the authoritative Core War rules, Redcode reference, and strategy guide. The system prompt instructs Claude to call this before its first response.
- `get_theory` fetches `modelwar.ai/docs/theory.md` — advanced Core War strategy theory for deeper analysis.
- Both are plain HTTPS fetches (no API authentication needed), handled by `AppSession`.

Web search is handled by Anthropic's built-in `web_search_20250305` tool (server-side, no client execution needed). The SSE parser handles both `server_tool_use` and `web_search_tool_result` block types for this.

### Key Services
- **APIClient** (`Services/APIClient.swift`): `@MainActor` async wrapper for modelwar.ai REST API (`https://www.modelwar.ai/api`). Full API spec at **https://modelwar.ai/openapi.json**.
- **KeychainService** (`Services/KeychainService.swift`): API key persistence via Security framework (parameterized for ModelWar + Anthropic keys)

### UI Structure
- **IDELayout**: HSplitView + VSplitView for resizable 4-panel desktop layout
- **CodeEditorView**: `NSViewRepresentable` wrapping `NSTextView` with Redcode syntax highlighting
- **ChatView**: ScrollViewReader + LazyVStack with 200-message render window. Uses `defaultScrollAnchor(.bottom)` plus `onChange(of: content.count)` to keep scrolled to bottom during streaming. Tool use and tool result messages carry the tool name through `ChatMessageRole` for per-tool summaries in `ChatBubble`.
- Battle replay uses WKWebView with bundled pmars-ts JavaScript

## File Organization

New Swift files in `ModelWarClient/` are auto-discovered (Xcode 16 `PBXFileSystemSynchronizedRootGroup`). Key directories:
- `Session/` — Observable state coordinators
- `Services/` — API clients (Claude + ModelWar), conversation manager, keychain
- `Models/` — Codable data structures (including Anthropic API types in `ClaudeAPI.swift`)
- `Views/` — SwiftUI views organized by feature (Chat/, Editor/, Battle/, Console/, Leaderboard/, etc.)
- `Utils/` — Constants, Logger (OSLog), RedcodeTemplates

## Dependencies

**Swift**: No external packages — SwiftUI, Foundation, Security, AppKit, WebKit, OSLog only.

## Configuration

- App sandbox is **enabled** with `com.apple.security.network.client` entitlement
- API base URLs and constants in `Utils/Constants.swift`
- Anthropic API key stored in Keychain, model selection persisted via UserDefaults
- Core War params must match server: core size 8000, max cycles 80000, 100 rounds

## Adding a New Tool

1. Add tool definition in `Services/ToolDefinitions.swift` → `modelWarTools` array
2. Add case in `AppSession.handleTool()` switch
3. Add API method in `APIClient` if needed
4. Optionally add display name/icon in `ChatBubble.swift`
