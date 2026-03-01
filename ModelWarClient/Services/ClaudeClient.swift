import Foundation
import OSLog

@MainActor
final class ClaudeClient {
    private var apiKey: String?
    private let log = Logger(subsystem: "com.saygoodnight.ModelWarClient", category: "ClaudeClient")
    /// Diagnostic log callback — surfaces internal logs to the app console
    var onDiagnosticLog: ((String) -> Void)?

    /// Dedicated session for SSE streaming with extended timeouts
    private let streamingSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300  // 5 min — allows for extended thinking
        config.timeoutIntervalForResource = 600  // 10 min — max total request time
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func setApiKey(_ key: String?) {
        apiKey = key
    }

    var hasApiKey: Bool { apiKey != nil }

    func streamMessage(request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        guard let apiKey else {
            log.error("streamMessage called without API key")
            return AsyncThrowingStream { $0.finish(throwing: ClaudeClientError.noApiKey) }
        }

        let url = URL(string: Constants.anthropicBaseURL)!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constants.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        let bodyData: Data
        do {
            bodyData = try encoder.encode(request)
            urlRequest.httpBody = bodyData
        } catch {
            log.error("Failed to encode request: \(error.localizedDescription)")
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        log.info("Sending request: model=\(request.model) messages=\(request.messages.count) maxTokens=\(request.maxTokens) bodySize=\(bodyData.count) bytes")
        onDiagnosticLog?("HTTP request: model=\(request.model) messages=\(request.messages.count) body=\(bodyData.count)B")

        let capturedRequest = urlRequest
        let capturedLog = log
        let capturedSession = streamingSession

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let (bytes, response) = try await capturedSession.bytes(for: capturedRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        capturedLog.error("Response is not HTTPURLResponse")
                        throw ClaudeClientError.invalidResponse
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                    capturedLog.info("HTTP \(httpResponse.statusCode) content-type=\(contentType)")

                    if httpResponse.statusCode != 200 {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        capturedLog.error("HTTP error \(httpResponse.statusCode): \(errorBody.prefix(500))")
                        throw ClaudeClientError.httpError(httpResponse.statusCode, errorBody)
                    }

                    // Parse SSE: only process "data: " lines, extract event type from JSON payload.
                    // bytes.lines skips empty lines, so we can't rely on them as event boundaries.
                    var eventCount = 0

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            capturedLog.warning("Stream cancelled after \(eventCount) events")
                            break
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let typeString = json["type"] as? String else {
                            capturedLog.warning("SSE data line missing 'type': \(jsonString.prefix(200))")
                            continue
                        }

                        guard let type = ClaudeStreamEventType(rawValue: typeString) else {
                            capturedLog.warning("Unrecognized SSE event type: '\(typeString)'")
                            continue
                        }

                        eventCount += 1
                        continuation.yield(ClaudeStreamEvent(type: type, data: data))
                    }

                    capturedLog.info("Stream finished: \(eventCount) events")
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        capturedLog.error("Stream error: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    } else {
                        capturedLog.info("Stream cancelled")
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum ClaudeClientError: LocalizedError {
    case noApiKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "No Anthropic API key configured."
        case .invalidResponse:
            return "Invalid response from Anthropic API."
        case .httpError(let code, let body):
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return "Anthropic API error (\(code)): \(message)"
            }
            return "Anthropic API error (\(code)): \(body.prefix(200))"
        }
    }
}
