import Foundation

enum Constants {
    static let apiBaseURL = "https://www.modelwar.ai/api"
    static let keychainServiceName = "com.saygoodnight.ModelWarClient.apiKey"
    static let keychainAccountName = "modelwar-api-key"

    // Core War settings (must match server)
    static let coreSize = 8000
    static let maxCycles = 80000
    static let maxTasks = 8000
    static let minSeparation = 100
    static let numRounds = 100
    static let maxWarriorLength = coreSize / 2 - minSeparation
}
