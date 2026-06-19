import Foundation
import SwiftUI

/// Member profile + current rate, from GET /v1/me.
struct MemberProfile: Codable, Equatable {
    var memberId: String
    var name: String
    var role: String
    var currency: String
    var baseRateCents: Int
    var effectiveRateCents: Int
    var qualityFactor: Double?
}

/// One day's coarse summary, pushed to POST /v1/metrics.
struct DailyMetric: Codable, Equatable {
    var date: String        // yyyy-MM-dd
    var entries: Int
    var wins: Int
    var losses: Int
    var wellbeing: Double?   // avg mood 1–5
    var dayScore: Int?       // overall 1–10
}

enum TeamAPIError: LocalizedError {
    case notConfigured, unauthorized, http(Int), badResponse
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No team server configured."
        case .unauthorized: return "Your seat is not authorized. Re-activate your license."
        case .http(let c): return "Server error (\(c))."
        case .badResponse: return "Unexpected server response."
        }
    }
}

/// Backend the app reads role/rate from and pushes daily summaries to.
protocol TeamAPI {
    func me() async throws -> MemberProfile
    func push(_ metric: DailyMetric) async throws -> Int   // effectiveRateCents
}

/// Local stand-in so the flow works without a backend. Echoes a plausible
/// rate adjusted by the day's wellbeing.
struct MockTeamAPI: TeamAPI {
    func me() async throws -> MemberProfile {
        MemberProfile(memberId: "mock-1", name: "You", role: "Developer",
                      currency: "EUR", baseRateCents: 8000,
                      effectiveRateCents: 8000, qualityFactor: 1.0)
    }
    func push(_ metric: DailyMetric) async throws -> Int {
        let base = 8000
        let factor = TeamMetrics.qualityFactor(wellbeing: metric.wellbeing,
                                               dayScore: metric.dayScore)
        return Int((Double(base) * factor).rounded())
    }
}

/// Real backend client (skeleton). Swap in by setting a base URL + token.
struct HTTPTeamAPI: TeamAPI {
    let baseURL: URL
    let token: String

    private func request(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TeamAPIError.badResponse }
        if http.statusCode == 401 { throw TeamAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw TeamAPIError.http(http.statusCode) }
        return data
    }

    func me() async throws -> MemberProfile {
        let data = try await request("v1/me", method: "GET")
        return try JSONDecoder().decode(MemberProfile.self, from: data)
    }

    func push(_ metric: DailyMetric) async throws -> Int {
        let body = try JSONEncoder().encode(metric)
        let data = try await request("v1/metrics", method: "POST", body: body)
        struct Result: Codable { var stored: Bool; var effectiveRateCents: Int }
        return try JSONDecoder().decode(Result.self, from: data).effectiveRateCents
    }
}

/// Pure helpers for building a day's metric — easy to unit test.
enum TeamMetrics {
    @MainActor
    static func dailyMetric(from store: DataStore, on day: Date) -> DailyMetric {
        let dayEntries = store.entries(on: day)
        let wins = dayEntries.filter { $0.quickKind == "win" }.count
        let losses = dayEntries.filter { $0.quickKind == "fail" }.count
        let moods = dayEntries.compactMap { $0.mood }
        let wellbeing = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return DailyMetric(date: f.string(from: day),
                           entries: dayEntries.count,
                           wins: wins, losses: losses,
                           wellbeing: wellbeing,
                           dayScore: store.dayRating(for: day))
    }

    /// Reference quality factor (the server owns the real one). 0.7…1.0.
    static func qualityFactor(wellbeing: Double?, dayScore: Int?) -> Double {
        var score = 0.85
        if let w = wellbeing { score = (w - 1) / 4 }          // 1–5 → 0–1
        else if let d = dayScore { score = Double(d - 1) / 9 } // 1–10 → 0–1
        return min(1.0, max(0.7, 0.7 + 0.3 * score))
    }
}

/// Drives team profile + sync, Pro/consent gated.
@MainActor
final class TeamManager: ObservableObject {
    static let shared = TeamManager()

    @AppStorage("teamSyncEnabled") var syncEnabled = false
    @AppStorage("teamBaseURL") var baseURLString = ""

    @Published private(set) var profile: MemberProfile?
    @Published var lastError: String?
    @Published var isBusy = false

    private var api: TeamAPI {
        if let url = URL(string: baseURLString), !baseURLString.isEmpty {
            return HTTPTeamAPI(baseURL: url, token: SeatToken.current ?? "")
        }
        return MockTeamAPI()
    }

    /// Run an API call; on 401 re-activate the seat (rotates the token) and
    /// retry once.
    private func withReauth<T>(_ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch TeamAPIError.unauthorized {
            guard await ProManager.shared.reactivate() else { throw TeamAPIError.unauthorized }
            return try await op()
        }
    }

    func refresh() async {
        guard syncEnabled else { return }
        isBusy = true; defer { isBusy = false }
        do { profile = try await withReauth { try await api.me() } }
        catch { lastError = error.localizedDescription }
    }

    func syncDay(_ store: DataStore, day: Date = Date()) async {
        guard syncEnabled else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let metric = TeamMetrics.dailyMetric(from: store, on: day)
            let effective = try await withReauth { try await api.push(metric) }
            if var p = profile { p.effectiveRateCents = effective; profile = p }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
