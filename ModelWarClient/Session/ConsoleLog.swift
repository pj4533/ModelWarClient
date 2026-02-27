import Foundation
import OSLog

@Observable
final class ConsoleLog {
    var entries: [ConsoleLogEntry] = []
    var filterLevel: ConsoleLogLevel? = nil

    var filteredEntries: [ConsoleLogEntry] {
        guard let filterLevel else { return entries }
        return entries.filter { $0.level == filterLevel }
    }

    func log(_ message: String, level: ConsoleLogLevel = .info, category: String = "General") {
        let entry = ConsoleLogEntry(level: level, message: message, category: category)
        entries.append(entry)

        switch level {
        case .info: AppLog.general.info("\(category): \(message)")
        case .warning: AppLog.general.warning("\(category): \(message)")
        case .error: AppLog.general.error("\(category): \(message)")
        case .debug: AppLog.general.debug("\(category): \(message)")
        }
    }

    func clear() {
        entries.removeAll()
    }
}
