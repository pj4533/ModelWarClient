import Foundation

enum ConsoleLogLevel: String, CaseIterable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
}

struct ConsoleLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: ConsoleLogLevel
    let message: String
    let category: String

    init(level: ConsoleLogLevel, message: String, category: String = "General") {
        self.timestamp = Date()
        self.level = level
        self.message = message
        self.category = category
    }
}
