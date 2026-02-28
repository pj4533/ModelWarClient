import SwiftUI

private let suggestionPool = [
    "Write me a competitive tournament warrior",
    "Upload a pspace scanner warrior",
    "Explain core war strategies for beginners",
    "Challenge the top player on the leaderboard",
    "Analyze my current warrior and suggest improvements",
    "Write a vampire warrior that converts enemies",
    "What's the best counter to an imp ring?",
    "Build a stone/imp hybrid warrior",
    "Explain how SPL bombing works",
    "Write a quickscanner that beats paper",
    "Help me climb the leaderboard",
    "What's my current win/loss record?",
    "Write a self-splitting bomber",
    "Explain the paper/rock/scissors metagame",
    "Create a dwarf-style bomber warrior",
    "How does pspace work in Core War?",
    "Write a silk warrior with decoy",
    "Challenge someone close to my rating",
    "Optimize my warrior for the current meta",
    "What are the most common warrior archetypes?",
    "Write a clear/imp warrior",
    "Explain how core size affects strategy",
    "Build a warrior that beats bombers",
]

struct ChatView: View {
    @Bindable var appSession: AppSession

    @State private var inputText = ""
    @State private var suggestions = pickSuggestions()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if appSession.agentSession.isConnected {
                    Label("Connected", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if appSession.agentSession.isConnecting {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Connecting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Disconnected", systemImage: "bolt.slash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            if appSession.agentSession.messages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("Ask the agent anything about Core War")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                sendSuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appSession.agentSession.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(8)
                    }
                    .onChange(of: appSession.agentSession.messages.count) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            ChatInputView(inputText: $inputText) {
                sendMessage()
            }
        }
    }

    private func sendSuggestion(_ text: String) {
        inputText = ""
        if appSession.agentSession.isConnected {
            appSession.agentSession.sendMessage(text)
        } else {
            appSession.startAgent(pendingMessage: text)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""

        if appSession.agentSession.isConnected {
            appSession.agentSession.sendMessage(text)
        } else {
            // Reconnect with pending message if disconnected
            appSession.startAgent(pendingMessage: text)
        }
    }

    private static func pickSuggestions() -> [String] {
        Array(suggestionPool.shuffled().prefix(3))
    }
}
