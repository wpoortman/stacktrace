import SwiftUI

/// OpenAI configuration: API key (stored in Keychain) and model. Includes a
/// Verify button that makes a tiny request to confirm the key works.
struct AISettingsView: View {
    @State private var apiKey: String = ""
    @AppStorage(AIConfig.modelDefaultsKey) private var model: String = AIConfig.defaultModel

    @State private var status: Status = .idle
    enum Status: Equatable { case idle, verifying, ok, failed(String) }

    var body: some View {
        Form {
            Section {
                SecureField("sk-…", text: $apiKey)
                Button("Save Key") { saveKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if Keychain.get(account: AIConfig.keychainAccount) != nil {
                    Label("A key is stored in your Keychain", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Create a key at platform.openai.com → API keys. This is separate from a ChatGPT subscription and billed per use. Stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
                Text("Default \(AIConfig.defaultModel) — cheap and good for text cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Verify Key") { verify() }
                        .disabled(status == .verifying)
                    if status == .verifying {
                        ProgressView().controlSize(.small)
                    }
                    statusLabel
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = Keychain.get(account: AIConfig.keychainAccount) ?? ""
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .idle, .verifying:
            EmptyView()
        case .ok:
            Label("Working", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle")
                .foregroundStyle(.red)
        }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Keychain.delete(account: AIConfig.keychainAccount)
        } else {
            Keychain.set(trimmed, account: AIConfig.keychainAccount)
        }
        status = .idle
    }

    private func verify() {
        saveKey()
        status = .verifying
        Task {
            do {
                try await EnhancementService.verifyKey()
                status = .ok
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}
