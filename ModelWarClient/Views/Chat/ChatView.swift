import SwiftUI

struct ChatView: View {
    @Bindable var appSession: AppSession

    @State private var inputText = ""

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

            Divider()

            ChatInputView(inputText: $inputText) {
                sendMessage()
            }
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
}
