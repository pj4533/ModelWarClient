import SwiftUI
import WebKit
import OSLog

struct BattleWebView: View {
    let battleSession: BattleSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Battle")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let battle = battleSession.currentBattle {
                    Spacer()
                    Text(battle.result.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.bold())
                        .foregroundStyle(resultColor(battle.result))
                    Text("\(battle.challengerWins)W-\(battle.defenderWins)L-\(battle.ties)T")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let replay = battleSession.currentReplay {
                    Picker("Round", selection: Binding(
                        get: { battleSession.selectedRound },
                        set: { battleSession.selectedRound = $0 }
                    )) {
                        ForEach(replay.roundResults, id: \.round) { round in
                            Text("R\(round.round)").tag(round.round)
                        }
                    }
                    .frame(width: 80)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            if battleSession.isLoadingReplay {
                VStack {
                    ProgressView("Loading replay...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let replay = battleSession.currentReplay {
                ReplayWebView(replay: replay, roundNumber: battleSession.selectedRound)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Challenge a player to see the battle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func resultColor(_ result: String) -> Color {
        switch result {
        case "challenger_win": return .green
        case "defender_win": return .red
        case "tie": return .yellow
        default: return .secondary
        }
    }
}

struct ReplayWebView: NSViewRepresentable {
    let replay: BattleReplay
    let roundNumber: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "battleBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        loadReplayHTML(webView: webView, context: context)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentRound != roundNumber {
            context.coordinator.currentRound = roundNumber
            sendReplayData(to: webView)
        }
    }

    private func loadReplayHTML(webView: WKWebView, context: Context) {
        if let htmlURL = Bundle.main.url(forResource: "replay", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // Fallback: load from project Resources directory during development
            let devPath = "/Users/pj4533/Developer/ModelWarClient/ModelWarClient/Resources/replay.html"
            if FileManager.default.fileExists(atPath: devPath) {
                let url = URL(fileURLWithPath: devPath)
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
        context.coordinator.currentRound = roundNumber

        // Wait for page load, then send data
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sendReplayData(to: webView)
        }
    }

    private func sendReplayData(to webView: WKWebView) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(replay),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        let js = "loadReplay(\(jsonString), \(roundNumber));"
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                AppLog.ui.error("Failed to send replay data: \(error.localizedDescription)")
            }
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var currentRound: Int = 1

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Handle messages from the WebView if needed
            if let body = message.body as? [String: Any] {
                AppLog.ui.debug("WebView message: \(String(describing: body))")
            }
        }
    }
}
