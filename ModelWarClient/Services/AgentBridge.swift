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
                    await MainActor.run {
                        self?.processLine(line)
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

    private func processLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let message = try decoder.decode(BridgeMessage.self, from: data)
            onMessage?(message)
        } catch {
            AppLog.bridge.error("Failed to parse: \(line.prefix(200)) — \(error)")
        }
    }
}

// MARK: - Bridge Protocol Types

enum BridgeCommand: Encodable {
    case startSession
    case userMessage(text: String)
    case setContext(apiKey: String, warriorCode: String, recentBattle: String?)
    case shutdown

    enum CodingKeys: String, CodingKey {
        case command, text
        case apiKey = "api_key"
        case warriorCode = "warrior_code"
        case recentBattle = "recent_battle"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .startSession:
            try container.encode("start_session", forKey: .command)
        case .userMessage(let text):
            try container.encode("user_message", forKey: .command)
            try container.encode(text, forKey: .text)
        case .setContext(let apiKey, let warriorCode, let recentBattle):
            try container.encode("set_context", forKey: .command)
            try container.encode(apiKey, forKey: .apiKey)
            try container.encode(warriorCode, forKey: .warriorCode)
            try container.encodeIfPresent(recentBattle, forKey: .recentBattle)
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
    case turnEnded
    case error(String)

    enum CodingKeys: String, CodingKey {
        case type, content, name, input, isError, message, reason
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
        case "turn_ended":
            self = .turnEnded
        case "error":
            let message = try container.decode(String.self, forKey: .message)
            self = .error(message)
        default:
            self = .error("Unknown message type: \(type)")
        }
    }
}
