import Foundation
import OSLog

@Observable
final class AgentBridge {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var readTask: Task<Void, Never>?

    var onMessage: ((BridgeMessage) -> Void)?
    var isRunning: Bool { process?.isRunning ?? false }

    private var projectRoot: String {
        if let bundlePath = Bundle.main.bundlePath as String? {
            let appDir = (bundlePath as NSString).deletingLastPathComponent
            if appDir.contains("DerivedData") {
                return sourceRoot
            }
            return appDir
        }
        return sourceRoot
    }

    private var sourceRoot: String {
        #if DEBUG
        return "/Users/pj4533/Developer/ModelWarClient"
        #else
        return (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        #endif
    }

    func start() {
        if let existingProcess = process, existingProcess.isRunning {
            AppLog.bridge.warning("Killing existing bridge process (PID: \(existingProcess.processIdentifier))")
            existingProcess.terminate()
        }
        readTask?.cancel()
        readTask = nil
        process = nil
        stdinPipe = nil
        stdoutPipe = nil

        let pythonPath = "\(projectRoot)/.venv/bin/python3"
        let scriptPath = "\(projectRoot)/modelwar_bridge.py"

        AppLog.bridge.info("Starting bridge process")
        AppLog.bridge.debug("Project root: \(self.projectRoot)")

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            AppLog.bridge.error("Python venv not found at \(pythonPath)")
            onMessage?(.error("Python venv not found. Run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"))
            return
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            AppLog.bridge.error("Bridge script not found at \(scriptPath)")
            onMessage?(.error("Bridge script not found at \(scriptPath)"))
            return
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)

        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"

        let homebrewPaths = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missingPaths = homebrewPaths.filter { !currentPath.contains($0) }
        if !missingPaths.isEmpty {
            env["PATH"] = (missingPaths + [currentPath]).joined(separator: ":")
        }
        process.environment = env

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe

        process.terminationHandler = { [weak self] proc in
            AppLog.bridge.info("Bridge process terminated with status \(proc.terminationStatus)")
            Task { @MainActor in
                if proc.terminationStatus != 0 {
                    self?.onMessage?(.error("Bridge process exited with code \(proc.terminationStatus)"))
                }
            }
        }

        do {
            try process.run()
            AppLog.bridge.info("Bridge process launched (PID: \(process.processIdentifier))")
        } catch {
            AppLog.bridge.error("Failed to launch bridge: \(error.localizedDescription)")
            onMessage?(.error("Failed to launch bridge: \(error.localizedDescription)"))
            return
        }

        readTask = Task { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            let stream = handle.bytes.lines
            do {
                for try await line in stream {
                    guard !Task.isCancelled else { break }
                    // Parse JSON off main thread to avoid pipe buffer deadlock
                    guard let message = self?.parseLine(line) else { continue }
                    await MainActor.run {
                        self?.onMessage?(message)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.onMessage?(.error("Bridge read error: \(error.localizedDescription)"))
                }
            }
        }

        Task {
            let handle = stderrPipe.fileHandleForReading
            let stream = handle.bytes.lines
            do {
                for try await line in stream {
                    AppLog.bridge.info("bridge: \(line)")
                }
            } catch {
                AppLog.bridge.debug("stderr stream closed")
            }
        }
    }

    func sendCommand(_ command: BridgeCommand) {
        guard let stdinPipe, process?.isRunning == true else {
            AppLog.bridge.warning("sendCommand called but bridge is not running")
            return
        }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(command),
              let jsonString = String(data: data, encoding: .utf8) else {
            AppLog.bridge.error("Failed to encode command")
            return
        }

        AppLog.bridge.debug("Sending command: \(jsonString)")
        let line = jsonString + "\n"
        // Ignore SIGPIPE to prevent crash when bridge process has exited
        signal(SIGPIPE, SIG_IGN)
        stdinPipe.fileHandleForWriting.write(Data(line.utf8))
    }

    func shutdown() {
        AppLog.bridge.info("Shutting down bridge")
        sendCommand(.shutdown)
        readTask?.cancel()
        readTask = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if let process = self?.process, process.isRunning {
                process.terminate()
            }
            self?.process = nil
            self?.stdinPipe = nil
            self?.stdoutPipe = nil
        }
    }

    /// Parse a JSON line into a BridgeMessage off the main thread.
    private nonisolated func parseLine(_ line: String) -> BridgeMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(BridgeMessage.self, from: data)
        } catch {
            AppLog.bridge.error("Failed to parse: \(line.prefix(200)) — \(error)")
            return nil
        }
    }
}

// MARK: - Bridge Protocol Types

enum BridgeCommand: Encodable {
    case startSession
    case userMessage(text: String)
    case setContext(warriorCode: String, recentBattle: String?)
    case toolResponse(requestId: String, data: String, isError: Bool)
    case shutdown

    enum CodingKeys: String, CodingKey {
        case command, text
        case warriorCode = "warrior_code"
        case recentBattle = "recent_battle"
        case requestId = "request_id"
        case data
        case isError = "is_error"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .startSession:
            try container.encode("start_session", forKey: .command)
        case .userMessage(let text):
            try container.encode("user_message", forKey: .command)
            try container.encode(text, forKey: .text)
        case .setContext(let warriorCode, let recentBattle):
            try container.encode("set_context", forKey: .command)
            try container.encode(warriorCode, forKey: .warriorCode)
            try container.encodeIfPresent(recentBattle, forKey: .recentBattle)
        case .toolResponse(let requestId, let data, let isError):
            try container.encode("tool_response", forKey: .command)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(data, forKey: .data)
            try container.encode(isError, forKey: .isError)
        case .shutdown:
            try container.encode("shutdown", forKey: .command)
        }
    }
}

enum BridgeMessage: Decodable {
    case sessionReady
    case agentText(content: String)
    case agentThinking(content: String)
    case agentToolUse(name: String, input: String)
    case agentToolResult(content: String, isError: Bool)
    case toolRequest(requestId: String, tool: String, arguments: [String: AnyCodableValue])
    case streamTextStart
    case streamTextDelta(text: String)
    case streamThinkingStart
    case streamThinkingDelta(text: String)
    case streamToolStart(name: String)
    case streamContentStop
    case turnEnded
    case log(message: String, level: String)
    case error(String)

    enum CodingKeys: String, CodingKey {
        case type, content, name, input, text, isError, message, reason, level
        case requestId, tool, arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "session_ready":
            self = .sessionReady
        case "agent_text":
            let content = try container.decode(String.self, forKey: .content)
            self = .agentText(content: content)
        case "agent_thinking":
            let content = try container.decode(String.self, forKey: .content)
            self = .agentThinking(content: content)
        case "agent_tool_use":
            let name = try container.decode(String.self, forKey: .name)
            let input = (try? container.decode(String.self, forKey: .input)) ?? ""
            self = .agentToolUse(name: name, input: input)
        case "agent_tool_result":
            let content = try container.decode(String.self, forKey: .content)
            let isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
            self = .agentToolResult(content: content, isError: isError)
        case "tool_request":
            let requestId = try container.decode(String.self, forKey: .requestId)
            let tool = try container.decode(String.self, forKey: .tool)
            let arguments = (try? container.decode([String: AnyCodableValue].self, forKey: .arguments)) ?? [:]
            self = .toolRequest(requestId: requestId, tool: tool, arguments: arguments)
        case "stream_text_start":
            self = .streamTextStart
        case "stream_text_delta":
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .streamTextDelta(text: text)
        case "stream_thinking_start":
            self = .streamThinkingStart
        case "stream_thinking_delta":
            let text = (try? container.decode(String.self, forKey: .text)) ?? ""
            self = .streamThinkingDelta(text: text)
        case "stream_tool_start":
            let name = (try? container.decode(String.self, forKey: .name)) ?? ""
            self = .streamToolStart(name: name)
        case "stream_content_stop":
            self = .streamContentStop
        case "turn_ended":
            self = .turnEnded
        case "log":
            let message = try container.decode(String.self, forKey: .message)
            let level = (try? container.decode(String.self, forKey: .level)) ?? "debug"
            self = .log(message: message, level: level)
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message)
        default:
            self = .error("Unknown message type: \(type)")
        }
    }
}

enum AnyCodableValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        case .bool: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .double(doubleVal)
        } else if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            self = .string("")
        }
    }
}
