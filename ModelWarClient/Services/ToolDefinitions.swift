import Foundation

enum ToolDefinitions {
    static var modelWarTools: [ClaudeTool] {
        [
            ClaudeTool(
                name: "upload_warrior",
                description: "Upload a Redcode warrior to modelwar.ai. Returns the warrior details including ID and instruction count.",
                inputSchema: schema(
                    properties: [
                        "name": ["type": "string", "description": "Name for the warrior"],
                        "redcode": ["type": "string", "description": "Redcode source code"],
                    ],
                    required: ["name", "redcode"]
                )
            ),
            ClaudeTool(
                name: "challenge_player",
                description: "Challenge another player to a Core War battle. Returns battle results including wins, losses, ties, and rating changes.",
                inputSchema: schema(
                    properties: [
                        "defender_id": ["type": "integer", "description": "ID of the player to challenge"],
                    ],
                    required: ["defender_id"]
                )
            ),
            ClaudeTool(
                name: "get_profile",
                description: "Get your current player profile including rating, win/loss record, and active warrior.",
                inputSchema: schema(properties: [:], required: [])
            ),
            ClaudeTool(
                name: "get_leaderboard",
                description: "Get the top 100 players on the modelwar.ai leaderboard with ratings and records.",
                inputSchema: schema(properties: [:], required: [])
            ),
            ClaudeTool(
                name: "get_player_profile",
                description: "View a player's public profile including rating, win/loss record, warrior source code, and recent battles.",
                inputSchema: schema(
                    properties: [
                        "player_id": ["type": "integer", "description": "ID of the player to look up"],
                    ],
                    required: ["player_id"]
                )
            ),
            ClaudeTool(
                name: "get_battle",
                description: "View a battle result including warrior Redcodes and rating changes for both players.",
                inputSchema: schema(
                    properties: [
                        "battle_id": ["type": "integer", "description": "ID of the battle"],
                    ],
                    required: ["battle_id"]
                )
            ),
            ClaudeTool(
                name: "get_battle_replay",
                description: "Get battle replay data including warrior source code, per-round results with seeds, and engine settings.",
                inputSchema: schema(
                    properties: [
                        "battle_id": ["type": "integer", "description": "ID of the battle"],
                    ],
                    required: ["battle_id"]
                )
            ),
            ClaudeTool(
                name: "get_battles",
                description: "View your battle history (paginated). Returns recent battles with results and rating changes.",
                inputSchema: schema(
                    properties: [
                        "page": ["type": "integer", "description": "Page number (default: 1)"],
                        "per_page": ["type": "integer", "description": "Results per page (default: 20, max: 100)"],
                    ],
                    required: []
                )
            ),
            ClaudeTool(
                name: "get_player_battles",
                description: "View a player's battle history (paginated). Returns their recent battles with results.",
                inputSchema: schema(
                    properties: [
                        "player_id": ["type": "integer", "description": "ID of the player"],
                        "page": ["type": "integer", "description": "Page number (default: 1)"],
                        "per_page": ["type": "integer", "description": "Results per page (default: 20, max: 100)"],
                    ],
                    required: ["player_id"]
                )
            ),
            ClaudeTool(
                name: "get_warrior",
                description: "View warrior details including Redcode source code.",
                inputSchema: schema(
                    properties: [
                        "warrior_id": ["type": "integer", "description": "ID of the warrior"],
                    ],
                    required: ["warrior_id"]
                )
            ),
            ClaudeTool(
                name: "upload_arena_warrior",
                description: "Upload an arena warrior (max 100 instructions). Arena is a 10-player free-for-all format.",
                inputSchema: schema(
                    properties: [
                        "name": ["type": "string", "description": "Name for the arena warrior"],
                        "redcode": ["type": "string", "description": "Redcode source code (max 100 instructions)"],
                        "auto_join": ["type": "boolean", "description": "Whether to auto-join arenas (default: true)"],
                    ],
                    required: ["name", "redcode"]
                )
            ),
            ClaudeTool(
                name: "start_arena",
                description: "Start a 10-player arena battle. Returns placements with scores and rating changes.",
                inputSchema: schema(properties: [:], required: [])
            ),
            ClaudeTool(
                name: "get_arena_leaderboard",
                description: "Get the arena leaderboard rankings.",
                inputSchema: schema(properties: [:], required: [])
            ),
            ClaudeTool(
                name: "get_arena",
                description: "View arena result including participants, placements, and scores.",
                inputSchema: schema(
                    properties: [
                        "arena_id": ["type": "integer", "description": "ID of the arena"],
                    ],
                    required: ["arena_id"]
                )
            ),
            ClaudeTool(
                name: "get_arena_replay",
                description: "Get arena replay data including warrior sources and per-round results with seeds.",
                inputSchema: schema(
                    properties: [
                        "arena_id": ["type": "integer", "description": "ID of the arena"],
                    ],
                    required: ["arena_id"]
                )
            ),
        ]
    }

    static var webSearchTool: ClaudeWebSearchTool {
        ClaudeWebSearchTool(maxUses: 5)
    }

    static func allTools() -> [AnyEncodable] {
        var tools: [AnyEncodable] = modelWarTools.map { AnyEncodable($0) }
        tools.append(AnyEncodable(webSearchTool))
        return tools
    }

    // MARK: - Schema Helper

    private static func schema(
        properties: [String: [String: String]],
        required: [String]
    ) -> [String: AnyEncodable] {
        var result: [String: AnyEncodable] = [
            "type": AnyEncodable("object"),
        ]

        // Build properties dict
        var propsDict: [String: Any] = [:]
        for (key, value) in properties {
            propsDict[key] = value
        }
        result["properties"] = AnyEncodable(propsDict)

        if !required.isEmpty {
            result["required"] = AnyEncodable(required)
        }

        return result
    }
}
