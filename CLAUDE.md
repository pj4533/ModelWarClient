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
- **ClaudeClient** (`Services/ClaudeClient.swift`): HTTP client with SSE streaming parser. Uses `URLSession.AsyncBytes` for server-sent events.
- **ConversationManager** (`Services/ConversationManager.swift`): Agentic tool loop. Manages conversation history, streams responses, and executes tool calls inline via async/await.
- **ToolDefinitions** (`Services/ToolDefinitions.swift`): All 16 ModelWar tool schemas + built-in web search tool.
- **SystemPrompt** (`Services/SystemPrompt.swift`): Core War expert system prompt.

### Tool Execution Cycle
1. ConversationManager streams API response, accumulates tool_use content blocks
2. On `stop_reason == "tool_use"`, executes each tool via `toolExecutor` callback
3. `AppSession.handleTool()` dispatches to the appropriate API call and returns result
4. ConversationManager appends tool results to history and loops back to API

Tools: `upload_warrior`, `challenge_player`, `get_profile`, `get_leaderboard`, `get_player_profile`, `get_battle`, `get_battle_replay`, `get_battles`, `get_player_battles`, `get_warrior`, `upload_arena_warrior`, `start_arena`, `get_arena_leaderboard`, `get_arena`, `get_arena_replay`

Web search is handled by Anthropic's built-in `web_search_20250305` tool (server-side, no client execution needed).

### Key Services
- **APIClient** (`Services/APIClient.swift`): `@MainActor` async wrapper for modelwar.ai REST API (`https://www.modelwar.ai/api`). Full API spec at **https://modelwar.ai/openapi.json**.
- **KeychainService** (`Services/KeychainService.swift`): API key persistence via Security framework (parameterized for ModelWar + Anthropic keys)

### UI Structure
- **IDELayout**: HSplitView + VSplitView for resizable 4-panel desktop layout
- **CodeEditorView**: `NSViewRepresentable` wrapping `NSTextView` with Redcode syntax highlighting
- **ChatView**: ScrollViewReader + LazyVStack with 200-message render window and throttled streaming scroll
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
