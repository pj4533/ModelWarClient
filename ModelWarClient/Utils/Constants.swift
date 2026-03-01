import Foundation

enum Constants {
    static let apiBaseURL = "https://www.modelwar.ai/api"
    static let keychainServiceName = "com.saygoodnight.ModelWarClient.apiKey"
    static let keychainAccountName = "modelwar-api-key"

    // Anthropic API
    static let anthropicBaseURL = "https://api.anthropic.com/v1/messages"
    static let anthropicAPIVersion = "2023-06-01"
    static let anthropicDefaultModel = "claude-sonnet-4-6"
    static let anthropicMaxTokens = 16384
    static let anthropicKeychainService = "com.saygoodnight.ModelWarClient.anthropicKey"
    static let anthropicKeychainAccount = "anthropic-api-key"
    static let anthropicAvailableModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6", "Sonnet 4.6 — Fast & capable"),
        ("claude-opus-4-6", "Opus 4.6 — Most intelligent"),
        ("claude-haiku-4-5", "Haiku 4.5 — Fastest"),
    ]

    // Core War settings (must match server)
    static let coreSize = 8000
    static let maxCycles = 80000
    static let maxTasks = 8000
    static let minSeparation = 100
    static let numRounds = 100
    static let maxWarriorLength = coreSize / 2 - minSeparation
}
