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
- **AppSession** (`Session/AppSession.swift`): Central `@Observable` coordinator — API key, player profile, warrior code, leaderboard, tool request handling. This is the heart of the app.
- **AgentSession** (`Session/AgentSession.swift`): Manages bridge lifecycle, chat message array, streaming state.
- **ConsoleLog** (`Session/ConsoleLog.swift`): Observable log collector with levels and categories.

### Python Bridge (Critical Path)
Swift communicates with Claude Agent SDK via a Python subprocess over **stdin/stdout JSON lines**:
- **AgentBridge** (`Services/AgentBridge.swift`): Spawns `.venv/bin/python3 modelwar_bridge.py`, manages Process/Pipe lifecycle, serializes `BridgeCommand` → JSON, deserializes JSON → `BridgeMessage`.
- **modelwar_bridge.py** (project root): Claude Agent SDK client, MCP tool definitions, session management. ~684 lines.
- Protocol: snake_case JSON lines. Swift sends commands (`user_message`, `set_context`, `tool_response`). Python sends events (`agent_text`, `stream_text_delta`, `tool_request`, `turn_ended`).

### Tool Request Cycle
1. Agent calls a tool → Python sends `tool_request` with `request_id` to Swift
2. `AppSession.handleToolRequest()` dispatches to the appropriate API call
3. Swift responds via `agentSession.sendToolResponse()` → Python receives and continues

Tools: `upload_warrior`, `challenge_player`, `get_profile`, `get_leaderboard`, `get_player_profile`, `get_battle`, `get_battle_replay`, `get_battles`, `get_player_battles`, `get_warrior`, `upload_arena_warrior`, `start_arena`, `get_arena_leaderboard`, `get_arena`, `get_arena_replay`

### Key Services
- **APIClient** (`Services/APIClient.swift`): `@MainActor` async wrapper for modelwar.ai REST API (`https://www.modelwar.ai/api`). Full API spec at **https://modelwar.ai/openapi.json**.
- **KeychainService** (`Services/KeychainService.swift`): API key persistence via Security framework

### UI Structure
- **IDELayout**: HSplitView + VSplitView for resizable 4-panel desktop layout
- **CodeEditorView**: `NSViewRepresentable` wrapping `NSTextView` with Redcode syntax highlighting
- **ChatView**: ScrollViewReader + LazyVStack with 200-message render window and throttled streaming scroll
- Battle replay uses WKWebView with bundled pmars-ts JavaScript

## File Organization

New Swift files in `ModelWarClient/` are auto-discovered (Xcode 16 `PBXFileSystemSynchronizedRootGroup`). Key directories:
- `Session/` — Observable state coordinators
- `Services/` — API client, bridge, keychain
- `Models/` — Codable data structures
- `Views/` — SwiftUI views organized by feature (Chat/, Editor/, Battle/, Console/, Leaderboard/, etc.)
- `Utils/` — Constants, Logger (OSLog), RedcodeTemplates

## Dependencies

**Swift**: No external packages — SwiftUI, Foundation, Security, AppKit, WebKit, OSLog only.

**Python** (`requirements.txt`): `claude-agent-sdk`, `mcp`. Virtual env at `.venv/`.

## Configuration

- App sandbox is **disabled** (required for Python subprocess)
- API base URL and Core War constants in `Utils/Constants.swift`
- Core War params must match server: core size 8000, max cycles 80000, 100 rounds

## Adding a New Tool

1. Add tool definition in `modelwar_bridge.py` → `list_tools()`
2. Add handler in `modelwar_bridge.py` → `tool_use()` function
3. Add case in `AppSession.handleToolRequest()` switch
4. Add API method in `APIClient` if needed
5. Optionally add display name/icon in `ChatBubble.swift`
