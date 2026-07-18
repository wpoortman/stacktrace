import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case anthropic
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google Gemini"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openAI: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .google: return "AIza..."
        }
    }

    var keyHelp: String {
        switch self {
        case .openAI:
            return "Create a key at platform.openai.com -> API keys."
        case .anthropic:
            return "Create a key in the Anthropic Console."
        case .google:
            return "Create a Gemini API key in Google AI Studio."
        }
    }
}

struct AIModelOption: Identifiable, Equatable {
    let provider: AIProvider
    let id: String
    let name: String
    let detail: String
    let tokenWindow: String
    let tokenUse: String
    let supportsJSONMode: Bool
}

enum AIModelCatalog {
    static let all: [AIModelOption] = [
        AIModelOption(provider: .openAI, id: "gpt-4o-mini", name: "GPT-4o mini",
                      detail: "Best default for fast, low-cost text cleanup and short summaries.",
                      tokenWindow: "128K tokens", tokenUse: "Low token cost", supportsJSONMode: true),
        AIModelOption(provider: .openAI, id: "gpt-4o", name: "GPT-4o",
                      detail: "Stronger wording and nuance for polished reports.",
                      tokenWindow: "128K tokens", tokenUse: "Medium token cost", supportsJSONMode: true),
        AIModelOption(provider: .openAI, id: "gpt-4.1-mini", name: "GPT-4.1 mini",
                      detail: "Good for longer exports where context size matters.",
                      tokenWindow: "1M tokens", tokenUse: "Low-medium token cost", supportsJSONMode: true),

        AIModelOption(provider: .anthropic, id: "claude-3-5-haiku-latest", name: "Claude 3.5 Haiku",
                      detail: "Fast drafting and cleanup with concise output.",
                      tokenWindow: "200K tokens", tokenUse: "Low token cost", supportsJSONMode: false),
        AIModelOption(provider: .anthropic, id: "claude-3-5-sonnet-latest", name: "Claude 3.5 Sonnet",
                      detail: "Balanced writing quality for richer summaries and reflections.",
                      tokenWindow: "200K tokens", tokenUse: "Medium token cost", supportsJSONMode: false),

        AIModelOption(provider: .google, id: "gemini-2.0-flash", name: "Gemini 2.0 Flash",
                      detail: "Fast, economical summaries and text cleanup.",
                      tokenWindow: "1M tokens", tokenUse: "Low token cost", supportsJSONMode: true),
        AIModelOption(provider: .google, id: "gemini-2.5-flash", name: "Gemini 2.5 Flash",
                      detail: "Better reasoning while staying quick for report generation.",
                      tokenWindow: "1M tokens", tokenUse: "Low-medium token cost", supportsJSONMode: true),
        AIModelOption(provider: .google, id: "gemini-2.5-pro", name: "Gemini 2.5 Pro",
                      detail: "Highest quality Gemini option for long, nuanced report summaries.",
                      tokenWindow: "1M tokens", tokenUse: "Higher token cost", supportsJSONMode: true),
    ]

    static func options(for provider: AIProvider) -> [AIModelOption] {
        all.filter { $0.provider == provider }
    }

    static func option(provider: AIProvider, model: String) -> AIModelOption? {
        options(for: provider).first { $0.id == model }
    }

    static func defaultModel(for provider: AIProvider) -> String {
        options(for: provider).first?.id ?? "gpt-4o-mini"
    }
}

/// Config keys shared between the settings pane and the service.
enum AIConfig {
    static let providerDefaultsKey = "aiProvider"
    static let modelDefaultsKey = "openAIModel"
    static let instructionsKey = "aiCustomInstructions"
    static let defaultModel = "gpt-4o-mini"
    private static var cachedAPIKeys: [AIProvider: String?] = [:]
    private static var loadedAPIKeys: Set<AIProvider> = []

    static var provider: AIProvider {
        let stored = UserDefaults.standard.string(forKey: providerDefaultsKey) ?? ""
        return AIProvider(rawValue: stored) ?? .openAI
    }

    static func keychainAccount(for provider: AIProvider = AIConfig.provider) -> String {
        switch provider {
        case .openAI: return "openai-api-key"
        case .anthropic: return "anthropic-api-key"
        case .google: return "google-gemini-api-key"
        }
    }

    private static func keyPresentDefaultsKey(for provider: AIProvider = AIConfig.provider) -> String {
        switch provider {
        case .openAI: return "openAIKeyPresent"
        case .anthropic: return "anthropicAIKeyPresent"
        case .google: return "googleAIKeyPresent"
        }
    }

    static var apiKey: String? {
        apiKey(for: provider)
    }

    static func apiKey(for provider: AIProvider) -> String? {
        if loadedAPIKeys.contains(provider) { return cachedAPIKeys[provider] ?? nil }
        let key = Keychain.get(account: keychainAccount(for: provider))
        cacheAPIKey(key, for: provider)
        return key
    }

    /// Cheap UI check. Avoids reading Keychain from SwiftUI body rendering,
    /// which can trigger repeated macOS password prompts for ad-hoc builds.
    static var hasAPIKey: Bool {
        hasAPIKey(for: provider)
    }

    static func hasAPIKey(for provider: AIProvider) -> Bool {
        if loadedAPIKeys.contains(provider) {
            return (cachedAPIKeys[provider] ?? nil)?.isEmpty == false
        }
        let defaultsKey = keyPresentDefaultsKey(for: provider)
        if UserDefaults.standard.object(forKey: defaultsKey) != nil {
            return UserDefaults.standard.bool(forKey: defaultsKey)
        }
        return false
    }

    static func storeAPIKey(_ key: String, for provider: AIProvider = AIConfig.provider) {
        Keychain.set(key, account: keychainAccount(for: provider))
        cacheAPIKey(key, for: provider)
    }

    static func deleteAPIKey(for provider: AIProvider = AIConfig.provider) {
        Keychain.delete(account: keychainAccount(for: provider))
        cacheAPIKey(nil, for: provider)
    }

    private static func cacheAPIKey(_ key: String?, for provider: AIProvider) {
        cachedAPIKeys[provider] = key
        loadedAPIKeys.insert(provider)
        UserDefaults.standard.set(key?.isEmpty == false,
                                  forKey: keyPresentDefaultsKey(for: provider))
    }

    /// Optional user instructions (tone of voice, style) added to the enhance
    /// prompt. Trimmed; empty when unset.
    static var customInstructions: String {
        (UserDefaults.standard.string(forKey: instructionsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelDefaultsKey)
        let trimmed = stored?.trimmingCharacters(in: .whitespaces) ?? ""
        if let option = AIModelCatalog.option(provider: provider, model: trimmed) {
            return option.id
        }
        return AIModelCatalog.defaultModel(for: provider)
    }

    static var modelOption: AIModelOption {
        AIModelCatalog.option(provider: provider, model: model)
            ?? AIModelCatalog.options(for: provider)[0]
    }
}

/// The editable text fields of an entry that can be enhanced.
struct EntryText: Equatable {
    var title: String
    var detail: String
    var wentWell: String
    var wentBad: String

    var isAllEmpty: Bool {
        [title, detail, wentWell, wentBad].allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

enum EnhancementError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No \(AIConfig.provider.displayName) API key. Add one in Settings -> AI."
        case .http(let code, let message):
            return "\(AIConfig.provider.displayName) error \(code): \(message)"
        case .badResponse:
            return "Unexpected response from \(AIConfig.provider.displayName)."
        }
    }
}

/// Calls the selected AI provider to fix spelling/grammar and lightly polish
/// text, returning enhanced values for the same fields. Empty fields are left
/// untouched.
enum EnhancementService {
    static func enhance(_ input: EntryText) async throws -> EntryText {
        // Only send non-empty fields so the model never invents content.
        var fields: [String: String] = [:]
        if !input.title.isEmpty { fields["title"] = input.title }
        if !input.detail.isEmpty { fields["detail"] = input.detail }
        if !input.wentWell.isEmpty { fields["wentWell"] = input.wentWell }
        if !input.wentBad.isEmpty { fields["wentBad"] = input.wentBad }
        guard !fields.isEmpty else { return input }

        var system = """
        You are an editor for short work-report notes. For each field, fix \
        spelling and grammar and lightly polish the phrasing for clarity and a \
        professional tone. Preserve the author's original meaning, first-person \
        voice, and roughly the same length. Do not invent facts, add new \
        information, or merge fields. Return ONLY a JSON object containing \
        exactly the same keys you were given, each mapped to its improved text.
        """
        let instructions = AIConfig.customInstructions
        if !instructions.isEmpty {
            system += """


            Additional style instructions from the user — follow these for tone \
            and voice, but still never invent facts or change the meaning:
            \(instructions)
            """
        }

        let payloadJSON = try JSONSerialization.data(withJSONObject: fields)
        let userContent = String(data: payloadJSON, encoding: .utf8) ?? "{}"

        let content = try await completion(system: system, user: userContent,
                                           temperature: 0.3, wantsJSON: true)
        let enhanced = try parseFields(from: content)
        return EntryText(
            title: enhanced["title"] ?? input.title,
            detail: enhanced["detail"] ?? input.detail,
            wentWell: enhanced["wentWell"] ?? input.wentWell,
            wentBad: enhanced["wentBad"] ?? input.wentBad
        )
    }

    /// Summarize a whole report into a short, readable TL;DR paragraph.
    static func summarize(_ reportText: String, userPerspective: String = "",
                          itemCount: Int? = nil) async throws -> String {
        let trimmed = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let perspective = userPerspective.trimmingCharacters(in: .whitespacesAndNewlines)

        var system = """
        You summarize a personal work report into a short TL;DR for a manager. \
        Write ONE concise, readable paragraph (about 3–5 sentences) in the \
        first person. Include the total number of logged items when provided. \
        Cover the main accomplishments and progress and note any significant \
        setbacks. If the user provided their own perspective on the period, \
        treat it as an additional report item and use it to decide emphasis and \
        tone, while grounding factual claims in the report. Do not invent facts \
        or add anything not supported by the report or the user's perspective. \
        Return plain text only — no markdown, headings, or preamble.
        """
        let instructions = AIConfig.customInstructions
        if !instructions.isEmpty {
            system += """


            Additional style instructions from the user — follow these for tone \
            and voice, but still never invent facts:
            \(instructions)
            """
        }

        let countContext = itemCount.map { "Total logged items: \($0)" } ?? ""
        let userContent: String
        if perspective.isEmpty {
            userContent = """
            \(countContext)

            Report content:
            \(trimmed)
            """
        } else {
            userContent = """
            \(countContext)

            Additional user perspective for this period:
            \(perspective)

            Report content:
            \(trimmed)
            """
        }

        return try await completion(system: system, user: userContent, temperature: 0.4)
    }

    /// Lightly polish a manually written report summary without changing meaning.
    static func enhanceSummary(_ summaryText: String) async throws -> String {
        let trimmed = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var system = """
        You are an editor for a personal work-report summary. Fix spelling and \
        grammar and lightly polish the phrasing for clarity and a professional \
        tone. Preserve the author's original meaning, first-person voice, and \
        roughly the same length. Do not invent facts, add new information, or \
        turn it into a list. Return plain text only — no markdown, headings, or \
        preamble.
        """
        let instructions = AIConfig.customInstructions
        if !instructions.isEmpty {
            system += """


            Additional style instructions from the user — follow these for tone \
            and voice, but still never invent facts or change the meaning:
            \(instructions)
            """
        }

        return try await completion(system: system, user: trimmed, temperature: 0.3)
    }

    /// Lightweight key check used by the Settings "Verify" button.
    static func verifyKey() async throws {
        _ = try await enhance(EntryText(title: "ok", detail: "", wentWell: "", wentBad: ""))
    }

    private static func parseFields(from content: String) throws -> [String: String] {
        let trimmed = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let contentData = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw EnhancementError.badResponse
        }
        var result: [String: String] = [:]
        for (k, v) in parsed {
            if let s = v as? String { result[k] = s }
        }
        return result
    }

    private static func completion(system: String, user: String,
                                   temperature: Double,
                                   wantsJSON: Bool = false) async throws -> String {
        guard let key = AIConfig.apiKey, !key.isEmpty else {
            throw EnhancementError.noKey
        }
        switch AIConfig.provider {
        case .openAI:
            return try await openAICompletion(system: system, user: user,
                                              apiKey: key, temperature: temperature,
                                              wantsJSON: wantsJSON)
        case .anthropic:
            return try await anthropicCompletion(system: system, user: user,
                                                 apiKey: key, temperature: temperature)
        case .google:
            return try await googleCompletion(system: system, user: user,
                                              apiKey: key, temperature: temperature,
                                              wantsJSON: wantsJSON)
        }
    }

    private static func openAICompletion(system: String, user: String,
                                         apiKey: String,
                                         temperature: Double,
                                         wantsJSON: Bool) async throws -> String {
        let body: [String: Any] = [
            "model": AIConfig.model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        var requestBody = body
        if wantsJSON && AIConfig.modelOption.supportsJSONMode {
            requestBody["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EnhancementError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EnhancementError.http(http.statusCode, extractAPIError(from: data) ?? "request failed")
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw EnhancementError.badResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func anthropicCompletion(system: String, user: String,
                                            apiKey: String,
                                            temperature: Double) async throws -> String {
        let body: [String: Any] = [
            "model": AIConfig.model,
            "max_tokens": 1_024,
            "temperature": temperature,
            "system": system,
            "messages": [
                ["role": "user", "content": user],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EnhancementError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EnhancementError.http(http.statusCode, extractAPIError(from: data) ?? "request failed")
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]],
            let text = content.compactMap({ $0["text"] as? String }).first
        else { throw EnhancementError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func googleCompletion(system: String, user: String,
                                         apiKey: String,
                                         temperature: Double,
                                         wantsJSON: Bool) async throws -> String {
        let escapedModel = AIConfig.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? AIConfig.model
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(escapedModel):generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var generationConfig: [String: Any] = ["temperature": temperature]
        if wantsJSON && AIConfig.modelOption.supportsJSONMode {
            generationConfig["responseMimeType"] = "application/json"
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [
                ["role": "user", "parts": [["text": user]]],
            ],
            "generationConfig": generationConfig,
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EnhancementError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw EnhancementError.http(http.statusCode, extractAPIError(from: data) ?? "request failed")
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.compactMap({ $0["text"] as? String }).first
        else { throw EnhancementError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAPIError(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = root["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let message = error["error"] as? String { return message }
        }
        if let message = root["message"] as? String { return message }
        return nil
    }
}
