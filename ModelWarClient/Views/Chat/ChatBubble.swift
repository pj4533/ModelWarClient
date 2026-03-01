import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    @State private var isExpanded = false

    var body: some View {
        switch message.role {
        case .toolUse, .toolResult:
            toolBubble
        default:
            messageBubble
        }
    }

    // MARK: - Standard message bubble (user, assistant, thinking)

    private var messageBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundStyle(roleLabelColor)
                    Text(message.content)
                        .font(contentFont)
                        .foregroundStyle(contentColor)
                        .textSelection(.enabled)
                }
                roleIcon
            } else {
                roleIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(roleLabel)
                        .font(.caption)
                        .foregroundStyle(roleLabelColor)
                    Text(message.content)
                        .font(contentFont)
                        .foregroundStyle(contentColor)
                        .textSelection(.enabled)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Compact tool bubble

    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                    .font(.caption)

                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(iconColor)

                if let summary = toolSummary {
                    Text("— " + summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Detail view — only when expanded
            if isExpanded, let detail = toolDetail {
                Divider()
                    .padding(.vertical, 4)

                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { isExpanded.toggle() }
    }

    // MARK: - Tool summary (collapsed one-liner)

    private var toolSummary: String? {
        switch message.role {
        case .toolUse(let name):
            return toolUseSummary(name: name, content: message.content)
        case .toolResult:
            return toolResultSummary(content: message.content)
        default:
            return nil
        }
    }

    // MARK: - Tool detail (expanded content)

    private var toolDetail: String? {
        switch message.role {
        case .toolUse(let name):
            return toolUseDetail(name: name, content: message.content)
        case .toolResult:
            return toolResultDetail(content: message.content)
        default:
            return nil
        }
    }

    // MARK: - Tool use summary per type

    private func toolUseSummary(name: String, content: String) -> String? {
        let json = message.parsedJSON

        switch name {
        case "upload_warrior":
            if let n = json?["name"] as? String { return "Uploading \"\(n)\"" }
            return "Uploading warrior"
        case "challenge_player":
            if let id = json?["defender_id"] { return "Challenging player #\(id)" }
            return "Challenging player"
        case "get_profile":
            return "Fetching profile..."
        case "get_leaderboard":
            return "Fetching leaderboard..."
        case "get_player_profile":
            if let id = json?["player_id"] { return "Looking up player #\(id)" }
            return "Looking up player..."
        case "get_battle":
            if let id = json?["battle_id"] { return "Loading battle #\(id)" }
            return "Loading battle..."
        case "get_battle_replay":
            if let id = json?["battle_id"] { return "Loading replay for battle #\(id)" }
            return "Loading replay..."
        case "get_battles":
            let page = json?["page"] ?? 1
            return "Loading battle history (page \(page))"
        case "get_player_battles":
            if let id = json?["player_id"] { return "Loading battles for player #\(id)" }
            return "Loading player battles..."
        case "get_warrior":
            if let id = json?["warrior_id"] { return "Loading warrior #\(id)" }
            return "Loading warrior..."
        case "upload_arena_warrior":
            if let n = json?["name"] as? String { return "Uploading \"\(n)\"" }
            return "Uploading arena warrior"
        case "start_arena":
            return "Starting arena battle..."
        case "get_arena_leaderboard":
            return "Fetching arena rankings..."
        case "get_arena":
            if let id = json?["arena_id"] { return "Loading arena #\(id)" }
            return "Loading arena..."
        case "get_arena_replay":
            if let id = json?["arena_id"] { return "Loading replay for arena #\(id)" }
            return "Loading arena replay..."
        case "web_search":
            if let q = json?["query"] as? String { return "\"\(q)\"" }
            return "Searching..."
        default:
            return nil
        }
    }

    // MARK: - Tool use detail per type

    private func toolUseDetail(name: String, content: String) -> String? {
        let json = message.parsedJSON

        switch name {
        case "upload_warrior", "upload_arena_warrior":
            if let code = json?["redcode"] as? String { return code }
            return content
        case "challenge_player":
            if let id = json?["defender_id"] { return "Defender ID: \(id)" }
            return nil
        case "get_profile", "get_leaderboard", "get_arena_leaderboard", "start_arena":
            return nil
        case "get_player_profile", "get_player_battles":
            if let id = json?["player_id"] { return "Player ID: \(id)" }
            return nil
        case "get_battle", "get_battle_replay":
            if let id = json?["battle_id"] { return "Battle ID: \(id)" }
            return nil
        case "get_battles":
            return nil
        case "get_warrior":
            if let id = json?["warrior_id"] { return "Warrior ID: \(id)" }
            return nil
        case "get_arena", "get_arena_replay":
            if let id = json?["arena_id"] { return "Arena ID: \(id)" }
            return nil
        case "web_search":
            return nil
        default:
            return content
        }
    }

    // MARK: - Tool result summary

    private func toolResultSummary(content: String) -> String? {
        if let json = message.parsedJSON {
            if let name = json["name"] as? String, json["instruction_count"] != nil {
                let count = json["instruction_count"]!
                return "Warrior \"\(name)\" uploaded (\(count) instructions)"
            }
            if let result = json["result"] as? String {
                return "Battle: \(result)"
            }
            if let name = json["name"] as? String, json["elo"] != nil {
                let elo = json["elo"]!
                return "\(name) (ELO: \(elo))"
            }
            if let error = json["error"] as? String {
                return error
            }
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Tool result detail

    private func toolResultDetail(content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return nil }
        return trimmed
    }

    // MARK: - Shared styling properties

    private var roleIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .frame(width: 20)
            .padding(.top, 2)
    }

    private var iconName: String {
        switch message.role {
        case .thinking: return "brain"
        case .assistant: return "bubble.left"
        case .toolUse(let name):
            switch name {
            case "upload_warrior": return "arrow.up.doc"
            case "challenge_player": return "figure.fencing"
            case "get_profile": return "person.crop.circle"
            case "get_leaderboard": return "trophy"
            case "get_player_profile": return "person.text.rectangle"
            case "get_battle": return "shield.lefthalf.filled"
            case "get_battle_replay": return "play.circle"
            case "get_battles": return "list.bullet.rectangle"
            case "get_player_battles": return "list.bullet.rectangle"
            case "get_warrior": return "doc.text.magnifyingglass"
            case "upload_arena_warrior": return "arrow.up.doc"
            case "start_arena": return "flag.checkered"
            case "get_arena_leaderboard": return "trophy"
            case "get_arena": return "flag.checkered"
            case "get_arena_replay": return "play.circle"
            case "web_search": return "magnifyingglass"
            default: return "wrench"
            }
        case .toolResult(let isError): return isError ? "xmark.circle" : "checkmark.circle"
        case .user: return "person"
        }
    }

    private var iconColor: Color {
        switch message.role {
        case .thinking: return .gray
        case .assistant: return .blue
        case .toolUse: return .orange
        case .toolResult(let isError): return isError ? .red : .green
        case .user: return .purple
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .thinking: return "Thinking"
        case .assistant: return "Claude"
        case .toolUse(let name): return friendlyToolName(name)
        case .toolResult(let isError): return isError ? "Error" : "Result"
        case .user: return "You"
        }
    }

    private var roleLabelColor: Color { iconColor }

    private var contentFont: Font {
        switch message.role {
        case .toolUse, .toolResult:
            return .system(.caption, design: .monospaced)
        case .thinking:
            return .callout.italic()
        default:
            return .callout
        }
    }

    private var contentColor: Color {
        switch message.role {
        case .thinking: return .secondary
        default: return .primary
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .thinking: return Color.gray.opacity(0.1)
        case .assistant: return Color.blue.opacity(0.05)
        case .toolUse: return Color.orange.opacity(0.08)
        case .toolResult(let isError): return isError ? Color.red.opacity(0.08) : Color.green.opacity(0.05)
        case .user: return Color.purple.opacity(0.08)
        }
    }

    /// Returns a friendly display name for tools
    private func friendlyToolName(_ name: String) -> String {
        switch name {
        case "upload_warrior": return "Upload Warrior"
        case "challenge_player": return "Challenge Player"
        case "get_profile": return "Get Profile"
        case "get_leaderboard": return "Get Leaderboard"
        case "get_player_profile": return "Player Profile"
        case "get_battle": return "Battle Details"
        case "get_battle_replay": return "Battle Replay"
        case "get_battles": return "Battle History"
        case "get_player_battles": return "Player Battles"
        case "get_warrior": return "Warrior Details"
        case "upload_arena_warrior": return "Upload Arena Warrior"
        case "start_arena": return "Start Arena"
        case "get_arena_leaderboard": return "Arena Leaderboard"
        case "get_arena": return "Arena Details"
        case "get_arena_replay": return "Arena Replay"
        case "web_search": return "Web Search"
        default: return name
        }
    }
}
