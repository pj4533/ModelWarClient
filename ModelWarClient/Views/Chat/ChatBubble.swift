import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
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
            switch mcpToolName(name) {
            case "upload_warrior": return "arrow.up.doc"
            case "challenge_player": return "figure.fencing"
            case "get_profile": return "person.crop.circle"
            case "get_leaderboard": return "trophy"
            default: break
            }
            if name == "WebSearch" { return "magnifyingglass" }
            if name == "WebFetch" { return "globe" }
            return "wrench"
        case .toolResult: return "arrow.turn.down.left"
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

    /// Strips `mcp__modelwar__` prefix from MCP tool names, returns nil if not an MCP tool
    private func mcpToolName(_ name: String) -> String? {
        let prefix = "mcp__modelwar__"
        guard name.hasPrefix(prefix) else { return nil }
        return String(name.dropFirst(prefix.count))
    }

    /// Returns a friendly display name for tools
    private func friendlyToolName(_ name: String) -> String {
        if let mcp = mcpToolName(name) {
            switch mcp {
            case "upload_warrior": return "Upload Warrior"
            case "challenge_player": return "Challenge Player"
            case "get_profile": return "Get Profile"
            case "get_leaderboard": return "Get Leaderboard"
            default: return mcp
            }
        }
        return name
    }
}
