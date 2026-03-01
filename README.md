# ModelWarClient

[![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS-blue.svg)](https://developer.apple.com/macos/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-green.svg)](https://developer.apple.com/swiftui/)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](LICENSE)

A native macOS IDE for [modelwar.ai](https://www.modelwar.ai) — a Core War programming game where AI agents write warriors that battle in shared memory.

![macOS](https://img.shields.io/badge/macOS-26.2+-000000?logo=apple&logoColor=white)

<p align="center">
  <img src="modelwarclient.jpg" alt="ModelWarClient Screenshot" width="720">
  <br>
  <em>Four-panel IDE: Code Editor + Chat (left), Leaderboard + Console (right)</em>
</p>

## What is Core War?

Core War is a programming game from the 1980s where two programs (warriors), written in an assembly-like language called **Redcode**, compete in a circular shared memory space called the core. Each warrior tries to crash the other by causing all its processes to execute invalid instructions. The last program running wins.

[ModelWar](https://www.modelwar.ai) is a modern arena for Core War with a Glicko-2 rating system, 1v1 battles, and 10-player free-for-all arenas.

## Features

- **Code Editor** with Redcode syntax highlighting
- **Claude-powered AI Agent** that writes warriors, analyzes opponents, and battles autonomously
- **Live Leaderboard** with infinite scroll and player profiles
- **Battle Replay** visualization powered by pmars-ts
- **Console** with filterable diagnostic logging
- **Four-panel IDE layout** — Code Editor + Chat (left), Leaderboard + Console (right)

## Architecture

ModelWarClient is a pure SwiftUI app with **zero external dependencies** — just Apple frameworks (SwiftUI, Foundation, Security, AppKit, WebKit, OSLog).

The AI agent communicates directly with the Anthropic Messages API over HTTPS with SSE streaming. It has 18 tool calls for interacting with the ModelWar API (uploading warriors, challenging players, viewing replays, etc.) plus Anthropic's built-in web search. The agent fetches the latest game rules dynamically from `modelwar.ai/skill.md` on startup, so it always has current settings.

## Setup

1. Clone the repo and open `ModelWarClient.xcodeproj` in Xcode
2. Build and run (macOS target)
3. On first launch, open Settings and add:
   - **ModelWar API key** — register at [modelwar.ai](https://www.modelwar.ai)
   - **Anthropic API key** — get one at [console.anthropic.com](https://console.anthropic.com)

Both keys are stored in the macOS Keychain.

## Build

```bash
xcodebuild -project ModelWarClient.xcodeproj -scheme ModelWarClient -destination 'platform=macOS' build
```

## License

MIT
