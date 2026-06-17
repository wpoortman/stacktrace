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

/// SCAFFOLD mock: accepts any non-empty key, infers plan from a prefix, and
/// signs locally so the flow works without a backend.
/// "TEAM-…" → 50 seats, "CUSTOM-…" → contact tier, anything else → individual.
struct MockLicenseService: LicenseService {
    func activate(key: String, deviceID: String) async throws -> SignedEntitlement {
        let k = key.trimmingCharacters(in: .whitespaces).uppercased()
        guard !k.isEmpty else { throw LicenseError.invalidKey }
        let plan: Plan = k.hasPrefix("TEAM") ? .team : (k.hasPrefix("CUSTOM") ? .custom : .individual)
        let seats = plan == .individual ? 1 : (plan == .team ? 50 : 9999)
        let ent = Entitlement(key: k, plan: plan, seats: seats, deviceID: deviceID,
                              expires: Date().addingTimeInterval(365 * 24 * 3600))
        return LicenseCrypto.sign(ent)
    }
    func deactivate(key: String, deviceID: String) async throws {}
}

/// Drives Pro state from a validated, cached entitlement.
@MainActor
final class ProManager: ObservableObject {
    static let shared = ProManager()

    @Published private(set) var entitlement: Entitlement?
    @Published var lastError: String?
    @Published var isWorking = false

    private let service: LicenseService = MockLicenseService()
    private let cacheKey = "licenseEntitlement"
    private let deviceKey = "licenseDeviceID"

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

    func deactivate() async {
        if let e = entitlement {
            try? await service.deactivate(key: e.key, deviceID: deviceID)
        }
        UserDefaults.standard.removeObject(forKey: cacheKey)
        entitlement = nil
    }
}
