import SwiftUI

/// AI configuration: provider, API key (stored in Keychain), model, and style
/// instructions. Includes a Verify button that makes a tiny request.
struct AISettingsView: View {
    @State private var apiKey: String = ""
    @State private var keyStored = false
    @AppStorage(AIConfig.providerDefaultsKey) private var provider: String = AIProvider.openAI.rawValue
    @AppStorage(AIConfig.modelDefaultsKey) private var model: String = AIConfig.defaultModel
    @AppStorage(AIConfig.instructionsKey) private var instructions: String = ""
    @AppStorage(AIConfig.periodSummaryPromptKey) private var periodSummaryPrompt = AIConfig.defaultPeriodSummaryPrompt

    @State private var status: Status = .idle
    enum Status: Equatable { case idle, verifying, ok, failed(String) }

    private var selectedProvider: AIProvider {
        AIProvider(rawValue: provider) ?? .openAI
    }

    private var modelOptions: [AIModelOption] {
        AIModelCatalog.options(for: selectedProvider)
    }

    private var selectedModel: AIModelOption {
        AIModelCatalog.option(provider: selectedProvider, model: model)
            ?? modelOptions[0]
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Choose which AI service Stacktrace should use for summaries and text enhancement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SecureField(selectedProvider.keyPlaceholder, text: $apiKey)
                HStack {
                    Button("Save Key") { saveKey() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if keyStored {
                        Button("Remove Key", role: .destructive) { removeKey() }
                    }
                }
                if keyStored {
                    Label("\(selectedProvider.displayName) key is stored in your Keychain",
                          systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("\(selectedProvider.displayName) API Key")
            } footer: {
                Text("\(selectedProvider.keyHelp) Stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Model", selection: $model) {
                    ForEach(modelOptions) { option in
                        Text("\(option.name) - \(option.detail) · \(option.tokenWindow)")
                            .tag(option.id)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedModel.detail)
                    Text("\(selectedModel.tokenWindow) context · \(selectedModel.tokenUse)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Model")
            } footer: {
                Text("Token window is the maximum context the model can consider. Token cost describes relative usage for the same report text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text("Describe the tone and style you want the AI to use…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 7)
                    }
                    SpellCheckTextEditor(text: $instructions)
                        .padding(4)
                }
                .frame(height: 90)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            } header: {
                Text("Style instructions")
            } footer: {
                Text("Optional. Added to every Enhance request to steer tone of voice and style — e.g. “Keep it concise and upbeat, in British English.” The AI still won't invent facts or change your meaning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SpellCheckTextEditor(text: $periodSummaryPrompt)
                    .padding(4)
                    .frame(height: 170)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor)))
                HStack {
                    Spacer()
                    Button("Restore Default") {
                        periodSummaryPrompt = AIConfig.defaultPeriodSummaryPrompt
                    }
                    .disabled(periodSummaryPrompt == AIConfig.defaultPeriodSummaryPrompt)
                }
            } header: {
                Text("Standalone summary prompt")
            } footer: {
                Text("System instructions used by Generate → Summary. Stacktrace supplies the selected period and its logged items separately. If left empty, the default prompt is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Verify Key") { verify() }
                        .disabled(status == .verifying || apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if status == .verifying {
                        ProgressView().controlSize(.small)
                    }
                    statusLabel
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            normalizeModel()
            loadKey()
        }
        .onChange(of: provider) { _ in
            status = .idle
            normalizeModel()
            loadKey()
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
            removeKey()
        } else {
            AIConfig.storeAPIKey(trimmed, for: selectedProvider)
            keyStored = true
            status = .idle
        }
    }

    private func removeKey() {
        AIConfig.deleteAPIKey(for: selectedProvider)
        apiKey = ""
        keyStored = false
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

    private func loadKey() {
        apiKey = AIConfig.apiKey(for: selectedProvider) ?? ""
        keyStored = AIConfig.hasAPIKey(for: selectedProvider)
    }

    private func normalizeModel() {
        if AIModelCatalog.option(provider: selectedProvider, model: model) == nil {
            model = AIModelCatalog.defaultModel(for: selectedProvider)
        }
    }
}
