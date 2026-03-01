import Foundation
import OSLog

@MainActor
final class ClaudeClient {
    private var apiKey: String?
    private let log = Logger(subsystem: "com.saygoodnight.ModelWarClient", category: "ClaudeClient")

    func setApiKey(_ key: String?) {
        apiKey = key
    }

    var hasApiKey: Bool { apiKey != nil }

    func streamMessage(request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        guard let apiKey else {
            return AsyncThrowingStream { $0.finish(throwing: ClaudeClientError.noApiKey) }
        }

        let url = URL(string: Constants.anthropicBaseURL)!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Constants.anthropicAPIVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        let capturedRequest = urlRequest
        let capturedLog = log

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: capturedRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw ClaudeClientError.invalidResponse
                    }

                    if httpResponse.statusCode != 200 {
                        // Collect error body
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        throw ClaudeClientError.httpError(httpResponse.statusCode, errorBody)
                    }

                    var eventType = ""
                    var dataBuffer = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            eventType = String(line.dropFirst(7))
                        } else if line.hasPrefix("data: ") {
                            dataBuffer = String(line.dropFirst(6))
                        } else if line.isEmpty {
                            // Empty line = event boundary
                            if !eventType.isEmpty, !dataBuffer.isEmpty {
                                if let type = ClaudeStreamEventType(rawValue: eventType),
                                   let data = dataBuffer.data(using: .utf8) {
                                    continuation.yield(ClaudeStreamEvent(type: type, data: data))
                                }
                            }
                            eventType = ""
                            dataBuffer = ""
                        }
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        capturedLog.error("Stream error: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    } else {
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
            // Try to extract error message from JSON body
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
