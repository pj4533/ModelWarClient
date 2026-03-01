import Foundation
import OSLog

enum AppLog {
    private static let subsystem = "com.saygoodnight.ModelWarClient"

    static let general = Logger(subsystem: subsystem, category: "General")
    static let session = Logger(subsystem: subsystem, category: "Session")
    static let api = Logger(subsystem: subsystem, category: "API")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
