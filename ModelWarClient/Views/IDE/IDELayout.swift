import SwiftUI

struct IDELayout: View {
    @Bindable var appSession: AppSession

    var body: some View {
        HSplitView {
            // Left panel: Code Editor (top) + Chat (bottom)
            VSplitView {
                codeEditorPanel
                    .frame(minHeight: 200)

                chatPanel
                    .frame(minHeight: 200)
            }
            .frame(minWidth: 400)

            // Right panel: Leaderboard (top) + Console (bottom)
            VStack(spacing: 0) {
                LeaderboardView(appSession: appSession)

                ConsoleView(consoleLog: appSession.consoleLog)
            }
            .frame(minWidth: 400)
        }
    }

    @ViewBuilder
    private var codeEditorPanel: some View {
        VStack(spacing: 0) {
            EditorToolbar(appSession: appSession)
            Divider()
            CodeEditorView(
                text: $appSession.warriorCode,
                onTextChange: { appSession.onWarriorCodeChanged() }
            )
        }
    }

    @ViewBuilder
    private var chatPanel: some View {
        ChatView(appSession: appSession)
    }
}
