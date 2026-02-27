import SwiftUI

struct ConsoleView: View {
    let consoleLog: ConsoleLog

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Console")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Filter", selection: Binding(
                    get: { consoleLog.filterLevel },
                    set: { consoleLog.filterLevel = $0 }
                )) {
                    Text("All").tag(ConsoleLogLevel?.none)
                    ForEach(ConsoleLogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(ConsoleLogLevel?.some(level))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Button {
                    consoleLog.clear()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(consoleLog.filteredEntries) { entry in
                            ConsoleEntryRow(entry: entry)
                                .id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("console-bottom")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: consoleLog.entries.count) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("console-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }
}

private struct ConsoleEntryRow: View {
    let entry: ConsoleLogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundStyle(.secondary)

            Text(entry.level.rawValue)
                .foregroundStyle(levelColor)
                .frame(width: 36, alignment: .leading)

            Text("[\(entry.category)]")
                .foregroundStyle(.secondary)

            Text(entry.message)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }
}
