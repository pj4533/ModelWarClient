#!/usr/bin/env python3
"""
ModelWar Bridge Script

Manages the Claude Agent SDK session for Core War strategy assistance.
Communicates with the Swift app via JSON lines over stdin/stdout.

Protocol:
  Input (stdin):  {"command": "start_session"} | {"command": "user_message", "text": "..."} |
                  {"command": "set_context", "api_key": "...", "warrior_code": "...", "recent_battle": "..."} |
                  {"command": "shutdown"}
  Output (stdout): JSON lines with type field (session_ready, agent_text, agent_tool_use, etc.)
"""

import asyncio
import json
import signal
import sys
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

## ModelWar API
You can perform API actions using curl with the user's API key. The API key will be provided via context.

Base URL: https://modelwar.ai/api

Endpoints:
- GET /api/me — Your profile (rating, wins, losses, warrior info)
- POST /api/warriors — Upload warrior. Body: {"name": "...", "redcode": "..."}
- POST /api/challenge — Challenge player. Body: {"defender_id": <id>}
- GET /api/leaderboard — Top 100 players
- GET /api/battles/<id>/replay — Battle replay data

All authenticated endpoints require: -H "Authorization: Bearer <api_key>"

## Your Role
1. Help users write competitive Redcode warriors
2. Analyze opponents and suggest counter-strategies
3. Research Core War strategies using WebSearch and WebFetch
4. Execute API actions (upload warriors, challenge players, check leaderboard) when asked
5. Explain battle results and suggest improvements
6. Go autonomous when asked — continuously improve warriors and battle

## Important Resources
- corewar.co.uk — Strategy guides and warrior archives
- corewar-docs.readthedocs.io — ICWS '94 standard documentation
- sal.discontinuity.info — Strategy Archive Library

When the user asks you to do something with the API, use Bash with curl to make the request.
When analyzing warriors, think about what archetype they are and what their weaknesses might be.
"""

# Context that gets injected with API key and warrior code
current_context = ""


def emit(msg: dict[str, Any]) -> None:
    """Write a JSON message to stdout."""
    line = json.dumps(msg)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def debug(msg: str) -> None:
    """Write debug message to stderr (visible in Xcode console)."""
    sys.stderr.write(f"[bridge] {msg}\n")
    sys.stderr.flush()


async def run_agent(
    client: ClaudeSDKClient,
    interrupt_flag: list[bool],
    user_message_flag: list[bool],
    query_active: list[bool],
) -> None:
    """Process messages from the Claude Agent SDK client."""
    debug("Listening for agent messages")
    msg_count = 0

    try:
        async for message in client.receive_messages():
            msg_count += 1
            msg_type = type(message).__name__

            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, TextBlock):
                        if block.text.strip():
                            emit({"type": "agent_text", "content": block.text})
                    elif isinstance(block, ThinkingBlock):
                        emit({"type": "agent_thinking", "content": block.thinking})
                    elif isinstance(block, ToolUseBlock):
                        input_str = json.dumps(block.input) if block.input else ""
                        emit({
                            "type": "agent_tool_use",
                            "name": block.name,
                            "input": input_str,
                        })
                    elif isinstance(block, ToolResultBlock):
                        if block.is_error:
                            content = ""
                            if isinstance(block.content, str):
                                content = block.content
                            elif isinstance(block.content, list):
                                parts = []
                                for item in block.content:
                                    if isinstance(item, dict) and "text" in item:
                                        parts.append(item["text"])
                                content = "\n".join(parts)
                            emit({
                                "type": "agent_tool_result",
                                "content": content,
                                "is_error": True,
                            })

            elif isinstance(message, ResultMessage):
                debug(f"ResultMessage received (is_error={message.is_error})")
                query_active[0] = False
                if interrupt_flag[0]:
                    debug("Ignoring ResultMessage from interrupt")
                    interrupt_flag[0] = False
                    continue
                if user_message_flag[0]:
                    debug("User message answered, turn complete")
                    user_message_flag[0] = False
                    emit({"type": "turn_ended"})
                    continue
                emit({"type": "turn_ended"})
                # Don't return — keep listening for more interactions
                continue

    except asyncio.CancelledError:
        raise
    except Exception as e:
        debug(f"Error: {e}")
        emit({"type": "error", "message": str(e)})


async def main() -> None:
    """Main loop: read commands from stdin, dispatch actions."""
    global current_context
    running = True
    client: ClaudeSDKClient | None = None
    agent_task: asyncio.Task | None = None
    interrupt_flag: list[bool] = [False]
    user_message_flag: list[bool] = [False]
    query_active: list[bool] = [False]

    loop = asyncio.get_event_loop()

    def handle_signal(sig, frame):
        nonlocal running
        running = False
        if agent_task and not agent_task.done():
            agent_task.cancel()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    while running:
        try:
            line = await reader.readline()
            if not line:
                break

            line_str = line.decode().strip()
            if not line_str:
                continue

            try:
                cmd = json.loads(line_str)
            except json.JSONDecodeError:
                emit({"type": "error", "message": f"Invalid JSON: {line_str}"})
                continue

            command = cmd.get("command")

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
                    allowed_tools=["Bash", "Read", "Glob", "Grep", "WebFetch", "WebSearch"],
                    disallowed_tools=["Write", "Edit"],
                    permission_mode="bypassPermissions",
                    setting_sources=["user"],
                    hooks={},
                )

                client = ClaudeSDKClient(options=options)

                debug("Connecting agent")
                await client.connect()
                agent_task = asyncio.create_task(
                    run_agent(client, interrupt_flag, user_message_flag, query_active)
                )
                await asyncio.sleep(0.1)

                emit({"type": "session_ready"})
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
                    await client.query(full_message)
                else:
                    emit({"type": "error", "message": "No active session"})

            elif command == "set_context":
                api_key = cmd.get("api_key", "")
                warrior_code = cmd.get("warrior_code", "")
                recent_battle = cmd.get("recent_battle", "")

                parts = []
                if api_key:
                    parts.append(f"[Context] API Key for curl requests: {api_key}")
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
            break
        except Exception as e:
            emit({"type": "error", "message": f"Bridge error: {str(e)}"})

    if client:
        try:
            await client.disconnect()
        except Exception:
            pass


if __name__ == "__main__":
    asyncio.run(main())
