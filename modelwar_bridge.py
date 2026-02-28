#!/usr/bin/env python3
"""
ModelWar Bridge Script

Manages the Claude Agent SDK session for Core War strategy assistance.
Communicates with the Swift app via JSON lines over stdin/stdout.

Protocol:
  Input (stdin):  {"command": "start_session"} | {"command": "user_message", "text": "..."} |
                  {"command": "set_context", "warrior_code": "...", "recent_battle": "..."} |
                  {"command": "tool_response", "request_id": "...", "data": "...", "is_error": false} |
                  {"command": "shutdown"}
  Output (stdout): JSON lines with type field (session_ready, agent_text, agent_tool_use, tool_request, etc.)
"""

import asyncio
import json
import signal
import sys
import threading
import time
import uuid
from typing import Any

from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    AssistantMessage,
    ResultMessage,
    TextBlock,
    ThinkingBlock,
    ToolUseBlock,
    ToolResultBlock,
)
from claude_agent_sdk.types import StreamEvent

from mcp.server import Server as MCPServer
import mcp.types as mcp_types

SYSTEM_PROMPT = """You are a Core War strategy expert and AI assistant integrated into ModelWarClient, a macOS IDE for modelwar.ai.

## Core War Overview
Core War is a programming game where two warriors (programs written in Redcode) compete in a shared circular memory (the "core"). Each warrior tries to eliminate the other by causing all its processes to execute DAT instructions.

## Redcode (ICWS '94 Standard)
Opcodes: DAT, MOV, ADD, SUB, MUL, DIV, MOD, JMP, JMZ, JMN, DJN, CMP/SEQ, SNE, SLT, SPL, NOP, LDP, STP
Modifiers: .A, .B, .AB, .BA, .F, .X, .I
Addressing modes: # (immediate), $ (direct), @ (B-indirect), < (B-predecrement), > (B-postincrement), * (A-indirect), { (A-predecrement), } (A-postincrement)

## ModelWar Settings
- Core size: 8,000 addresses
- Max cycles: 80,000 per round
- Max processes: 8,000 per warrior
- Min separation: 100
- Rounds per battle: 100
- Max warrior length: 3,850 instructions

## Warrior Archetypes
- **Imp**: Simple MOV 0,1 — walks through core. Hard to kill but rarely wins.
- **Bomber/Stone**: Drops DAT bombs at regular intervals to hit opponents.
- **Scanner**: Searches for non-zero cells, then bombs those locations.
- **Replicator/Silk**: Copies itself to new locations, creating redundancy.
- **Vampire**: Redirects opponent processes to run its own code.
- **Paper**: Replicator designed to beat scissors (scanners).
- **Scissors**: Scanner designed to beat stones/bombers.
- **Stone**: Bomber designed to beat scissors/scanners.

## Strategy Concepts
- **Bombing**: Writing DAT instructions to enemy territory to kill processes.
- **Scanning**: Checking core addresses for non-zero values to find opponents.
- **SPL chains**: Using SPL to create many processes for resilience.
- **Decoy**: Filling core with harmless non-zero values to confuse scanners.
- **Core clear**: Systematically zeroing out the entire core.
- **Quick scan**: Fast initial scan before switching to main strategy.

## Your Tools
You have these tools to interact with modelwar.ai:

### 1v1 Combat
- **upload_warrior(name, redcode)** — Upload a Redcode warrior. Returns warrior details including ID and instruction count.
- **challenge_player(defender_id)** — Challenge a player by their ID. Returns battle results with wins, losses, ties, and rating changes.
- **get_profile()** — Get your current profile, rating, and active warrior info.
- **get_leaderboard()** — Get the top 100 players with ratings and records.

### Player & Battle Info
- **get_player_profile(player_id)** — View a player's public profile, rating, warrior source, and recent battles.
- **get_battle(battle_id)** — View a battle result with warrior Redcodes and rating changes.
- **get_battle_replay(battle_id)** — Get replay data with per-round results and seeds.
- **get_battles(page?, per_page?)** — View your battle history (paginated).
- **get_player_battles(player_id, page?, per_page?)** — View a player's battle history.
- **get_warrior(warrior_id)** — View warrior details including Redcode source.

### Arena (10-player free-for-all)
- **upload_arena_warrior(name, redcode, auto_join?)** — Upload an arena warrior (max 100 instructions).
- **start_arena()** — Start a 10-player arena battle. Returns placements and rating changes.
- **get_arena_leaderboard()** — Get arena rankings.
- **get_arena(arena_id)** — View arena result with participants and scores.
- **get_arena_replay(arena_id)** — Get arena replay data.

Authentication is handled automatically — just call the tools directly. Do NOT use Bash or curl for API calls.

## Your Role
1. Help users write competitive Redcode warriors
2. Analyze opponents and suggest counter-strategies
3. Research Core War strategies using WebSearch and WebFetch
4. Execute API actions (upload warriors, challenge players, check leaderboard) using your tools
5. Explain battle results and suggest improvements
6. Go autonomous when asked — continuously improve warriors and battle

## Important Resources
- corewar.co.uk — Strategy guides and warrior archives
- corewar-docs.readthedocs.io — ICWS '94 standard documentation
- sal.discontinuity.info — Strategy Archive Library

## BLOCKED DOMAINS — DO NOT FETCH
⚠️ CRITICAL: The following domains are known to hang indefinitely and will freeze the entire session.
NEVER use WebFetch on these domains. If you need information from them, use WebSearch instead.

- vyznev.net — ALWAYS hangs, NEVER fetch any URL from this domain
- Any URL containing "vyznev.net" must be SKIPPED entirely

If a search result links to vyznev.net, DO NOT follow the link. Summarize from the search snippet or find an alternative source.

When analyzing warriors, think about what archetype they are and what their weaknesses might be.
"""

# Context that gets injected with warrior code
current_context = ""

# Pending tool requests awaiting Swift responses
pending_requests: dict[str, asyncio.Future] = {}

# Async queue for commands from stdin thread
command_queue: asyncio.Queue | None = None

# Event loop reference for thread-safe operations
main_loop: asyncio.AbstractEventLoop | None = None

# --- MCP Server ---

mcp_server = MCPServer("modelwar")


@mcp_server.list_tools()
async def list_tools() -> list[mcp_types.Tool]:
    return [
        mcp_types.Tool(
            name="upload_warrior",
            description="Upload a Redcode warrior to modelwar.ai. Returns the warrior details including ID and instruction count.",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Name for the warrior"},
                    "redcode": {"type": "string", "description": "Redcode source code"},
                },
                "required": ["name", "redcode"],
            },
        ),
        mcp_types.Tool(
            name="challenge_player",
            description="Challenge another player to a Core War battle. Returns battle results including wins, losses, ties, and rating changes.",
            inputSchema={
                "type": "object",
                "properties": {
                    "defender_id": {"type": "integer", "description": "ID of the player to challenge"},
                },
                "required": ["defender_id"],
            },
        ),
        mcp_types.Tool(
            name="get_profile",
            description="Get your current player profile including rating, win/loss record, and active warrior.",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        mcp_types.Tool(
            name="get_leaderboard",
            description="Get the top 100 players on the modelwar.ai leaderboard with ratings and records.",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        mcp_types.Tool(
            name="get_player_profile",
            description="View a player's public profile including rating, win/loss record, warrior source code, and recent battles.",
            inputSchema={
                "type": "object",
                "properties": {
                    "player_id": {"type": "integer", "description": "ID of the player to look up"},
                },
                "required": ["player_id"],
            },
        ),
        mcp_types.Tool(
            name="get_battle",
            description="View a battle result including warrior Redcodes and rating changes for both players.",
            inputSchema={
                "type": "object",
                "properties": {
                    "battle_id": {"type": "integer", "description": "ID of the battle"},
                },
                "required": ["battle_id"],
            },
        ),
        mcp_types.Tool(
            name="get_battle_replay",
            description="Get battle replay data including warrior source code, per-round results with seeds, and engine settings.",
            inputSchema={
                "type": "object",
                "properties": {
                    "battle_id": {"type": "integer", "description": "ID of the battle"},
                },
                "required": ["battle_id"],
            },
        ),
        mcp_types.Tool(
            name="get_battles",
            description="View your battle history (paginated). Returns recent battles with results and rating changes.",
            inputSchema={
                "type": "object",
                "properties": {
                    "page": {"type": "integer", "description": "Page number (default: 1)"},
                    "per_page": {"type": "integer", "description": "Results per page (default: 20, max: 100)"},
                },
            },
        ),
        mcp_types.Tool(
            name="get_player_battles",
            description="View a player's battle history (paginated). Returns their recent battles with results.",
            inputSchema={
                "type": "object",
                "properties": {
                    "player_id": {"type": "integer", "description": "ID of the player"},
                    "page": {"type": "integer", "description": "Page number (default: 1)"},
                    "per_page": {"type": "integer", "description": "Results per page (default: 20, max: 100)"},
                },
                "required": ["player_id"],
            },
        ),
        mcp_types.Tool(
            name="get_warrior",
            description="View warrior details including Redcode source code.",
            inputSchema={
                "type": "object",
                "properties": {
                    "warrior_id": {"type": "integer", "description": "ID of the warrior"},
                },
                "required": ["warrior_id"],
            },
        ),
        mcp_types.Tool(
            name="upload_arena_warrior",
            description="Upload an arena warrior (max 100 instructions). Arena is a 10-player free-for-all format.",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Name for the arena warrior"},
                    "redcode": {"type": "string", "description": "Redcode source code (max 100 instructions)"},
                    "auto_join": {"type": "boolean", "description": "Whether to auto-join arenas (default: true)"},
                },
                "required": ["name", "redcode"],
            },
        ),
        mcp_types.Tool(
            name="start_arena",
            description="Start a 10-player arena battle. Returns placements with scores and rating changes.",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        mcp_types.Tool(
            name="get_arena_leaderboard",
            description="Get the arena leaderboard rankings.",
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        mcp_types.Tool(
            name="get_arena",
            description="View arena result including participants, placements, and scores.",
            inputSchema={
                "type": "object",
                "properties": {
                    "arena_id": {"type": "integer", "description": "ID of the arena"},
                },
                "required": ["arena_id"],
            },
        ),
        mcp_types.Tool(
            name="get_arena_replay",
            description="Get arena replay data including warrior sources and per-round results with seeds.",
            inputSchema={
                "type": "object",
                "properties": {
                    "arena_id": {"type": "integer", "description": "ID of the arena"},
                },
                "required": ["arena_id"],
            },
        ),
    ]


@mcp_server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[mcp_types.TextContent]:
    debug(f"MCP call_tool: {name} args={arguments}")
    try:
        result = await bridge_request(name, arguments)
        debug(f"MCP call_tool result: {result[:100]}")
        return [mcp_types.TextContent(type="text", text=result)]
    except asyncio.TimeoutError:
        debug(f"MCP call_tool TIMEOUT: {name}")
        raise Exception(f"Tool request timed out: {name}")
    except Exception as e:
        debug(f"MCP call_tool ERROR: {name} — {e}")
        raise Exception(f"Tool request failed: {e}")


async def bridge_request(tool: str, arguments: dict) -> str:
    """Send a tool request to Swift and await the response."""
    request_id = str(uuid.uuid4())
    loop = asyncio.get_event_loop()
    future = loop.create_future()
    pending_requests[request_id] = future

    debug(f"bridge_request: emitting tool_request {request_id[:8]} for {tool}")
    emit_log(f"Tool request: {tool}", "info")
    emit({
        "type": "tool_request",
        "request_id": request_id,
        "tool": tool,
        "arguments": arguments,
    })

    t0 = time.monotonic()
    try:
        result = await asyncio.wait_for(future, timeout=30.0)
        elapsed = time.monotonic() - t0
        debug(f"bridge_request: resolved {request_id[:8]}")
        emit_log(f"Tool resolved: {tool} ({elapsed:.1f}s)", "debug")
        return result
    except asyncio.TimeoutError:
        elapsed = time.monotonic() - t0
        debug(f"bridge_request: TIMEOUT {request_id[:8]} — pending_requests has {len(pending_requests)} entries")
        emit_log(f"Tool TIMEOUT: {tool} after {elapsed:.1f}s", "error")
        raise
    finally:
        pending_requests.pop(request_id, None)


# --- Stdin Thread ---

def _stdin_reader_thread(loop: asyncio.AbstractEventLoop) -> None:
    """Read stdin in a dedicated thread so tool_response is always processed.

    This runs independently of the asyncio event loop, ensuring that
    tool_response commands are handled even when client.query() blocks
    the event loop with synchronous subprocess I/O.
    """
    debug("stdin thread started")
    try:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue
            try:
                cmd = json.loads(line)
            except json.JSONDecodeError:
                debug(f"stdin thread: invalid JSON: {line[:80]}")
                continue

            command = cmd.get("command")
            debug(f"stdin thread: received command={command}")

            if command == "tool_response":
                # Resolve futures directly from thread (thread-safe)
                request_id = cmd.get("request_id")
                debug(f"stdin thread: tool_response for {request_id and request_id[:8]}")
                if request_id and request_id in pending_requests:
                    future = pending_requests[request_id]
                    if not future.done():
                        is_error = cmd.get("is_error", False)
                        data = cmd.get("data", "")
                        if is_error:
                            loop.call_soon_threadsafe(future.set_exception, Exception(data))
                        else:
                            loop.call_soon_threadsafe(future.set_result, data)
                        debug(f"stdin thread: resolved future {request_id[:8]}")
                    else:
                        debug(f"stdin thread: future already done {request_id[:8]}")
                else:
                    debug(f"stdin thread: unknown request_id {request_id}")
            else:
                # Queue other commands for async processing
                asyncio.run_coroutine_threadsafe(command_queue.put(cmd), loop)
    except Exception as e:
        debug(f"stdin thread error: {e}")
    debug("stdin thread exited")


# --- Helpers ---


def emit(msg: dict[str, Any]) -> None:
    """Write a JSON message to stdout with pipe health monitoring."""
    line = json.dumps(msg) + "\n"
    t0 = time.monotonic()
    sys.stdout.write(line)
    sys.stdout.flush()
    elapsed = time.monotonic() - t0
    if elapsed > 0.1:
        # Log to stderr since stdout is what's blocked
        sys.stderr.write(f"[bridge] WARN: emit blocked for {elapsed:.2f}s\n")
        sys.stderr.flush()


def emit_log(message: str, level: str = "debug") -> None:
    """Send a log message to the Swift Console view via stdout."""
    emit({"type": "log", "message": message, "level": level})


def debug(msg: str) -> None:
    """Write debug message to stderr (visible in Xcode console)."""
    sys.stderr.write(f"[bridge] {msg}\n")
    sys.stderr.flush()


def _extract_tool_result_content(block: ToolResultBlock) -> str:
    """Extract text content from a ToolResultBlock."""
    if isinstance(block.content, str):
        return block.content
    if isinstance(block.content, list):
        parts = []
        for item in block.content:
            if isinstance(item, dict) and "text" in item:
                parts.append(item["text"])
        return "\n".join(parts)
    return ""


async def run_agent(
    client: ClaudeSDKClient,
    interrupt_flag: list[bool],
    user_message_flag: list[bool],
    query_active: list[bool],
) -> None:
    """Process messages from the Claude Agent SDK client."""
    debug("Listening for agent messages")
    msg_count = 0
    streamed_text = False  # Track if we streamed text this turn

    try:
        async for message in client.receive_messages():
            msg_count += 1
            if msg_count % 50 == 0:
                debug(f"msg#{msg_count} type={type(message).__name__} (heartbeat)")
            else:
                msg_type = type(message).__name__
                debug(f"msg#{msg_count} type={msg_type}")

            if isinstance(message, StreamEvent):
                event = message.event
                event_type = event.get("type")

                if event_type == "content_block_start":
                    cb = event.get("content_block", {})
                    cb_type = cb.get("type")
                    if cb_type == "tool_use":
                        emit({"type": "stream_tool_start", "name": cb.get("name", "")})
                    elif cb_type == "thinking":
                        emit({"type": "stream_thinking_start"})
                    elif cb_type == "text":
                        emit({"type": "stream_text_start"})
                        streamed_text = True

                elif event_type == "content_block_delta":
                    delta = event.get("delta", {})
                    delta_type = delta.get("type")
                    if delta_type == "text_delta":
                        emit({"type": "stream_text_delta", "text": delta.get("text", "")})
                    elif delta_type == "thinking_delta":
                        emit({"type": "stream_thinking_delta", "text": delta.get("thinking", "")})

                elif event_type == "content_block_stop":
                    emit({"type": "stream_content_stop"})

                continue  # Don't fall through to AssistantMessage handling

            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        # Skip if we already streamed text this turn
                        if streamed_text:
                            continue
                        if block.text.strip():
                            emit({"type": "agent_text", "content": block.text})
                    elif isinstance(block, ThinkingBlock):
                        # Skip if streaming was active (thinking was streamed)
                        if streamed_text:
                            continue
                        emit({"type": "agent_thinking", "content": block.thinking})
                    elif isinstance(block, ToolUseBlock):
                        input_str = json.dumps(block.input) if block.input else ""
                        emit({
                            "type": "agent_tool_use",
                            "name": block.name,
                            "input": input_str,
                        })
                    elif isinstance(block, ToolResultBlock):
                        content = _extract_tool_result_content(block)
                        emit({
                            "type": "agent_tool_result",
                            "content": content,
                            "is_error": block.is_error,
                        })

            elif isinstance(message, ResultMessage):
                debug(f"ResultMessage received (is_error={message.is_error})")
                query_active[0] = False
                streamed_text = False  # Reset for next turn
                if interrupt_flag[0]:
                    debug("Ignoring ResultMessage from interrupt")
                    interrupt_flag[0] = False
                    continue
                if user_message_flag[0]:
                    debug("User message answered, turn complete")
                    user_message_flag[0] = False
                    emit_log("Turn ended", "debug")
                    emit({"type": "turn_ended"})
                    continue
                emit_log("Turn ended", "debug")
                emit({"type": "turn_ended"})
                continue

    except asyncio.CancelledError:
        debug("run_agent: cancelled")
        emit_log("Agent task cancelled", "warning")
        raise
    except Exception as e:
        debug(f"Error in run_agent: {e}")
        emit_log(f"Agent error: {e}", "error")
        emit({"type": "error", "message": str(e)})

    debug(f"run_agent: exiting after {msg_count} messages")
    emit_log(f"Agent message stream ended ({msg_count} messages)", "warning")


async def main() -> None:
    """Main loop: read commands from stdin thread queue, dispatch actions."""
    global current_context, command_queue, main_loop
    running = True
    client: ClaudeSDKClient | None = None
    agent_task: asyncio.Task | None = None
    interrupt_flag: list[bool] = [False]
    user_message_flag: list[bool] = [False]
    query_active: list[bool] = [False]

    main_loop = asyncio.get_event_loop()
    command_queue = asyncio.Queue()

    def handle_signal(sig, frame):
        nonlocal running
        running = False
        if agent_task and not agent_task.done():
            agent_task.cancel()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    # Start stdin reader in a background thread so tool_response
    # commands are always processed, even when client.query() blocks
    stdin_thread = threading.Thread(
        target=_stdin_reader_thread,
        args=(main_loop,),
        daemon=True,
    )
    stdin_thread.start()

    while running:
        try:
            # Read commands from the queue (populated by stdin thread)
            try:
                cmd = await asyncio.wait_for(command_queue.get(), timeout=0.5)
            except asyncio.TimeoutError:
                continue

            command = cmd.get("command")
            debug(f"main loop: processing command={command}")

            if command == "start_session":
                if client:
                    debug("Session already active")
                    continue

                options = ClaudeAgentOptions(
                    system_prompt={
                        "type": "preset",
                        "preset": "claude_code",
                        "append": SYSTEM_PROMPT,
                    },
                    include_partial_messages=True,
                    allowed_tools=[
                        "Read", "Glob", "Grep", "WebFetch", "WebSearch",
                        "mcp__modelwar__upload_warrior",
                        "mcp__modelwar__challenge_player",
                        "mcp__modelwar__get_profile",
                        "mcp__modelwar__get_leaderboard",
                        "mcp__modelwar__get_player_profile",
                        "mcp__modelwar__get_battle",
                        "mcp__modelwar__get_battle_replay",
                        "mcp__modelwar__get_battles",
                        "mcp__modelwar__get_player_battles",
                        "mcp__modelwar__get_warrior",
                        "mcp__modelwar__upload_arena_warrior",
                        "mcp__modelwar__start_arena",
                        "mcp__modelwar__get_arena_leaderboard",
                        "mcp__modelwar__get_arena",
                        "mcp__modelwar__get_arena_replay",
                    ],
                    disallowed_tools=["Write", "Edit", "Bash"],
                    permission_mode="bypassPermissions",
                    setting_sources=["user"],
                    hooks={},
                    mcp_servers={
                        "modelwar": {
                            "type": "sdk",
                            "name": "modelwar",
                            "instance": mcp_server,
                        }
                    },
                )

                client = ClaudeSDKClient(options=options)

                debug("Connecting agent")
                await client.connect()
                agent_task = asyncio.create_task(
                    run_agent(client, interrupt_flag, user_message_flag, query_active)
                )
                await asyncio.sleep(0.1)

                emit({"type": "session_ready"})
                emit_log("Session started", "info")
                debug("Session ready")

            elif command == "user_message":
                text = cmd.get("text", "")
                if not text:
                    continue
                if client:
                    debug(f"User message: {text[:60]}")

                    # Prepend context if available
                    full_message = text
                    if current_context:
                        full_message = f"{current_context}\n\nUser message: {text}"

                    user_message_flag[0] = True
                    if query_active[0]:
                        interrupt_flag[0] = True
                        try:
                            await client.interrupt()
                        except Exception:
                            pass
                    query_active[0] = True
                    # Run as task so main loop stays free
                    asyncio.create_task(client.query(full_message))
                else:
                    emit({"type": "error", "message": "No active session"})

            elif command == "set_context":
                warrior_code = cmd.get("warrior_code", "")
                recent_battle = cmd.get("recent_battle", "")

                parts = []
                if warrior_code:
                    parts.append(f"[Context] Current warrior code in editor:\n```redcode\n{warrior_code}\n```")
                if recent_battle:
                    parts.append(f"[Context] {recent_battle}")

                current_context = "\n".join(parts)
                debug("Context updated")

            elif command == "shutdown":
                if agent_task and not agent_task.done():
                    agent_task.cancel()
                    try:
                        await agent_task
                    except asyncio.CancelledError:
                        pass
                if client:
                    await client.disconnect()
                    client = None
                running = False

        except asyncio.CancelledError:
            debug("main loop: CancelledError, breaking")
            break
        except Exception as e:
            debug(f"main loop error: {e}")
            emit({"type": "error", "message": f"Bridge error: {str(e)}"})

    debug(f"main loop exited (running={running})")
    if client:
        try:
            await client.disconnect()
        except Exception:
            pass
    debug("bridge process exiting")


if __name__ == "__main__":
    asyncio.run(main())
