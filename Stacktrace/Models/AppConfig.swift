import Foundation

/// Build-wide configuration. The Team API URL is fixed in release builds and
/// only overridable in local debug builds.
enum AppConfig {
    /// The deployed backend. Empty = run offline against the mock until set.
    /// TODO: set to the production URL once the backend is live,
    /// e.g. "https://api.stacktrace.app".
    static let productionTeamBaseURL = ""

    static let devURLKey = "teamDevBaseURL"

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Production web admin (used when no backend origin is resolved).
    static let productionAdminURL = URL(string: "https://stacktrace.app/admin")!

    /// Web admin URL — same origin as the resolved API (so a dev domain points
    /// the Admin button at the local/staging backend), else production.
    static var adminURL: URL {
        if let base = teamBaseURL,
           var c = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            c.path = "/admin"
            c.query = nil
            if let url = c.url { return url }
        }
        return productionAdminURL
    }

    static let productionPricingURL = URL(string: "https://stacktrace.app/pricing")!

    /// Pricing/checkout URL — same origin as the resolved backend if set.
    static var pricingURL: URL {
        if let base = teamBaseURL,
           var c = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            c.path = "/pricing"
            c.query = nil
            if let url = c.url { return url }
        }
        return productionPricingURL
    }

    /// Resolved Team API base URL: a debug-only dev override if set, otherwise
    /// the production default. `nil` → use the offline mock.
    static var teamBaseURL: URL? {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: devURLKey),
           let url = normalizedURL(s) {
            return url
        }
        #endif
        return normalizedURL(productionTeamBaseURL)
    }

    /// Accept a host typed with or without a scheme; reject anything that isn't
    /// a valid http(s) URL with a host (prevents malformed open URLs / -50).
    static func normalizedURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
