import Foundation

/// Config keys shared between the settings pane and the service.
enum AIConfig {
    static let keychainAccount = "openai-api-key"
    static let modelDefaultsKey = "openAIModel"
    static let defaultModel = "gpt-4o-mini"

    static var apiKey: String? {
        Keychain.get(account: keychainAccount)
    }

    static var model: String {
        let stored = UserDefaults.standard.string(forKey: modelDefaultsKey)
        let trimmed = stored?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? defaultModel : trimmed
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
            return "No OpenAI API key. Add one in Settings → AI."
        case .http(let code, let message):
            return "OpenAI error \(code): \(message)"
        case .badResponse:
            return "Unexpected response from OpenAI."
        }
    }
}

/// Calls the OpenAI Chat Completions API to fix spelling/grammar and lightly
/// polish the entry's text, returning enhanced values for the same fields.
/// Empty fields are left untouched.
enum EnhancementService {
    static func enhance(_ input: EntryText) async throws -> EntryText {
        guard let key = AIConfig.apiKey, !key.isEmpty else {
            throw EnhancementError.noKey
        }

        // Only send non-empty fields so the model never invents content.
        var fields: [String: String] = [:]
        if !input.title.isEmpty { fields["title"] = input.title }
        if !input.detail.isEmpty { fields["detail"] = input.detail }
        if !input.wentWell.isEmpty { fields["wentWell"] = input.wentWell }
        if !input.wentBad.isEmpty { fields["wentBad"] = input.wentBad }
        guard !fields.isEmpty else { return input }

        let system = """
        You are an editor for short work-report notes. For each field, fix \
        spelling and grammar and lightly polish the phrasing for clarity and a \
        professional tone. Preserve the author's original meaning, first-person \
        voice, and roughly the same length. Do not invent facts, add new \
        information, or merge fields. Return ONLY a JSON object containing \
        exactly the same keys you were given, each mapped to its improved text.
        """

        let payloadJSON = try JSONSerialization.data(withJSONObject: fields)
        let userContent = String(data: payloadJSON, encoding: .utf8) ?? "{}"

        let body: [String: Any] = [
            "model": AIConfig.model,
            "temperature": 0.3,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userContent],
            ],
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EnhancementError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = extractAPIError(from: data) ?? "request failed"
            throw EnhancementError.http(http.statusCode, message)
        }

        let enhanced = try parseFields(from: data)
        return EntryText(
            title: enhanced["title"] ?? input.title,
            detail: enhanced["detail"] ?? input.detail,
            wentWell: enhanced["wentWell"] ?? input.wentWell,
            wentBad: enhanced["wentBad"] ?? input.wentBad
        )
    }

    /// Lightweight key check used by the Settings "Verify" button.
    static func verifyKey() async throws {
        _ = try await enhance(EntryText(title: "ok", detail: "", wentWell: "", wentBad: ""))
    }

    private static func parseFields(from data: Data) throws -> [String: String] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            let contentData = content.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any]
        else {
            throw EnhancementError.badResponse
        }
        var result: [String: String] = [:]
        for (k, v) in parsed {
            if let s = v as? String { result[k] = s }
        }
        return result
    }

    private static func extractAPIError(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        return message
    }
}
