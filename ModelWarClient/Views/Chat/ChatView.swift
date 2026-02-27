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

                if !appSession.agentSession.isConnected {
                    Button {
                        appSession.startAgent()
                    } label: {
                        Label("Connect", systemImage: "bolt")
                            .font(.caption)
                    }
                } else {
                    Label("Connected", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
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

        if !appSession.agentSession.isConnected {
            appSession.startAgent()
            // Queue the message to send after connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                appSession.agentSession.sendMessage(text)
            }
        } else {
            appSession.agentSession.sendMessage(text)
        }
        inputText = ""
    }
}
