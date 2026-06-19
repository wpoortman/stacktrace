import Foundation
import CryptoKit

enum Plan: String, Codable {
    case individual, team, custom
    var title: String {
        switch self {
        case .individual: return "Individual"
        case .team: return "Team"
        case .custom: return "Custom"
        }
    }
}

/// What a valid license grants. Signed by the server; verified offline here.
struct Entitlement: Codable, Equatable {
    var key: String
    var plan: Plan
    var seats: Int
    var deviceID: String
    var expires: Date
}

struct SignedEntitlement: Codable {
    var payload: Entitlement
    var signatureB64: String
}

/// Offline verification of a signed entitlement.
///
/// SCAFFOLD: the keypair is derived from a fixed seed so the bundled mock can
/// sign and this can verify, all locally. For production, replace `publicKey`
/// with your server's real Ed25519 public key (raw bytes) and delete the
/// private key — signing happens only on your backend.
enum LicenseCrypto {
    static let signingKey: Curve25519.Signing.PrivateKey = {
        let seed = SHA256.hash(data: Data("stacktrace.dev.licensing.v1".utf8))
        return try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(seed))
    }()
    static var publicKey: Curve25519.Signing.PublicKey { signingKey.publicKey }

    static func canonical(_ e: Entitlement) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(e)) ?? Data()
    }

    static func sign(_ e: Entitlement) -> SignedEntitlement {
        let sig = try! signingKey.signature(for: canonical(e))
        return SignedEntitlement(payload: e, signatureB64: sig.base64EncodedString())
    }

    static func verify(_ s: SignedEntitlement) -> Bool {
        guard let sig = Data(base64Encoded: s.signatureB64) else { return false }
        return publicKey.isValidSignature(sig, for: canonical(s.payload))
    }
}

enum LicenseError: LocalizedError {
    case invalidKey, seatsFull, network
    var errorDescription: String? {
        switch self {
        case .invalidKey: return "That license key wasn't recognized."
        case .seatsFull: return "All seats for this license are in use."
        case .network: return "Couldn't reach the license server."
        }
    }
}

/// Swap this for a Lemon Squeezy / Paddle / custom backend implementation.
protocol LicenseService {
    func activate(key: String, deviceID: String) async throws -> SignedEntitlement
    func deactivate(key: String, deviceID: String) async throws
}

/// Plan inferred from a key prefix (used by mock and as a local fallback).
func planForKey(_ key: String) -> (plan: Plan, seats: Int) {
    let k = key.trimmingCharacters(in: .whitespaces).uppercased()
    if k.hasPrefix("TEAM") { return (.team, 50) }
    if k.hasPrefix("CUSTOM") { return (.custom, 9999) }
    return (.individual, 1)
}

/// SCAFFOLD mock: accepts any non-empty key, infers plan from a prefix, and
/// signs locally so the flow works without a backend.
struct MockLicenseService: LicenseService {
    func activate(key: String, deviceID: String) async throws -> SignedEntitlement {
        let k = key.trimmingCharacters(in: .whitespaces).uppercased()
        guard !k.isEmpty else { throw LicenseError.invalidKey }
        let (plan, seats) = planForKey(k)
        let ent = Entitlement(key: k, plan: plan, seats: seats, deviceID: deviceID,
                              expires: Date().addingTimeInterval(365 * 24 * 3600))
        return LicenseCrypto.sign(ent)
    }
    func deactivate(key: String, deviceID: String) async throws {}
}

/// The seat token issued by the backend on activation, used as the API Bearer.
enum SeatToken {
    private static let account = "seat-token"
    static var current: String? { Keychain.get(account: account) }
    static func set(_ token: String) { Keychain.set(token, account: account) }
    static func clear() { Keychain.delete(account: account) }
}

/// Real activation against the agency backend: POST /v1/activate consumes a
/// seat and returns a Sanctum seat token, which we store for API auth. A local
/// signed entitlement is still produced so Pro gating verifies offline.
struct HTTPLicenseService: LicenseService {
    let baseURL: URL

    private struct ActivateBody: Codable { let key: String; let deviceID: String }
    private struct ActivateResponse: Codable { let token: String }

    func activate(key: String, deviceID: String) async throws -> SignedEntitlement {
        let k = key.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { throw LicenseError.invalidKey }

        var req = URLRequest(url: baseURL.appendingPathComponent("v1/activate"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(ActivateBody(key: k, deviceID: deviceID))

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LicenseError.network }
        if http.statusCode == 409 { throw LicenseError.seatsFull }
        guard (200..<300).contains(http.statusCode) else { throw LicenseError.invalidKey }

        let token = try JSONDecoder().decode(ActivateResponse.self, from: data).token
        SeatToken.set(token)

        // Local entitlement for offline Pro gating (server is source of truth
        // for role/rate via /v1/me).
        let (plan, seats) = planForKey(k)
        let ent = Entitlement(key: k, plan: plan, seats: seats, deviceID: deviceID,
                              expires: Date().addingTimeInterval(365 * 24 * 3600))
        return LicenseCrypto.sign(ent)
    }

    func deactivate(key: String, deviceID: String) async throws {
        SeatToken.clear()
    }
}

/// Drives Pro state from a validated, cached entitlement.
@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()

    @Published private(set) var entitlement: Entitlement?
    @Published var lastError: String?
    @Published var isWorking = false

    private let cacheKey = "licenseEntitlement"
    private let deviceKey = "licenseDeviceID"

    /// Use the real backend when a team server URL is configured; otherwise the
    /// offline mock. (Keeps the offline path identical.)
    private var service: LicenseService {
        if let s = UserDefaults.standard.string(forKey: "teamBaseURL"),
           !s.isEmpty, let url = URL(string: s) {
            return HTTPLicenseService(baseURL: url)
        }
        return MockLicenseService()
    }

    var isPro: Bool { (entitlement?.expires ?? .distantPast) > Date() }
    var planTitle: String { entitlement?.plan.title ?? "Free" }

    var deviceID: String {
        if let s = UserDefaults.standard.string(forKey: deviceKey) { return s }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    init() { loadCached() }

    private func loadCached() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let signed = try? JSONDecoder().decode(SignedEntitlement.self, from: data),
              LicenseCrypto.verify(signed),
              signed.payload.deviceID == deviceID else {
            entitlement = nil
            return
        }
        entitlement = signed.payload
    }

    func activate(_ key: String) async {
        lastError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let signed = try await service.activate(key: key, deviceID: deviceID)
            guard LicenseCrypto.verify(signed) else {
                lastError = "Invalid license signature."
                return
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(signed), forKey: cacheKey)
            entitlement = signed.payload
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-run activation with the stored key (e.g. after a 401 / rotated seat).
    @discardableResult
    func reactivate() async -> Bool {
        guard let key = entitlement?.key else { return false }
        await activate(key)
        return isPro
    }

    func deactivate() async {
        if let e = entitlement {
            try? await service.deactivate(key: e.key, deviceID: deviceID)
        }
        SeatToken.clear()
        UserDefaults.standard.removeObject(forKey: cacheKey)
        entitlement = nil
    }
}
