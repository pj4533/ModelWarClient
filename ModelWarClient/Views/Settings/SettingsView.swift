import SwiftUI

struct SettingsView: View {
    @Bindable var appSession: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var anthropicKeyInput = ""
    @State private var playerNameInput = ""
    @State private var isRegistering = false
    @State private var registrationError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("ModelWar Settings")
                .font(.title2.bold())

            if appSession.apiKey != nil {
                existingKeySection
            } else {
                newKeySection
            }

            Divider()

            anthropicKeySection

            Divider()

            modelPickerSection

            Divider()

            registerSection

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450, height: 560)
        .onAppear {
            apiKeyInput = appSession.apiKey ?? ""
            anthropicKeyInput = appSession.anthropicKey ?? ""
        }
    }

    @ViewBuilder
    private var existingKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ModelWar API Key")
                .font(.headline)

            HStack {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    appSession.setApiKey(apiKeyInput)
                }
                .disabled(apiKeyInput.isEmpty)
            }

            if let player = appSession.player {
                Label("Logged in as: \(player.name)", systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("Logout") {
                appSession.logout()
                apiKeyInput = ""
                anthropicKeyInput = ""
                dismiss()
            }
            .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var newKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ModelWar API Key")
                .font(.headline)

            Text("Enter your ModelWar API key, or register a new account below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                SecureField("Paste your API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    appSession.setApiKey(apiKeyInput)
                }
                .disabled(apiKeyInput.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var anthropicKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anthropic API Key")
                .font(.headline)

            Text("Required for the AI chat assistant. Get one at console.anthropic.com.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                SecureField("sk-ant-...", text: $anthropicKeyInput)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    appSession.setAnthropicKey(anthropicKeyInput)
                }
                .disabled(anthropicKeyInput.isEmpty)
            }

            if appSession.anthropicKey != nil {
                Label("Anthropic key configured", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    @ViewBuilder
    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Model")
                .font(.headline)

            Picker("Model", selection: $appSession.selectedModel) {
                ForEach(Constants.anthropicAvailableModels, id: \.id) { model in
                    Text(model.label).tag(model.id)
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var registerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Register New Account")
                .font(.headline)

            HStack {
                TextField("Player name", text: $playerNameInput)
                    .textFieldStyle(.roundedBorder)

                Button("Register") {
                    register()
                }
                .disabled(playerNameInput.count < 2 || isRegistering)
            }

            if isRegistering {
                ProgressView()
                    .scaleEffect(0.7)
            }

            if let error = registrationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func register() {
        isRegistering = true
        registrationError = nil

        Task {
            do {
                let result = try await appSession.apiClient.register(name: playerNameInput)
                appSession.setApiKey(result.apiKey)
                apiKeyInput = result.apiKey
                playerNameInput = ""
                appSession.consoleLog.log("Registered as \(result.name)", category: "API")
            } catch {
                registrationError = error.localizedDescription
                appSession.consoleLog.log("Registration failed: \(error.localizedDescription)", level: .error, category: "API")
            }
            isRegistering = false
        }
    }
}
