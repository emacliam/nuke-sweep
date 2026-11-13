import CryptoKit
import Foundation
import Security

enum TrialAccess {
    static let licenceKey = "nuke.signedLicence"
    static let duration: TimeInterval = 14 * 86_400

    enum Status: Equatable {
        case unrestricted, invalidConfiguration, licensed(Date?), notStarted, trial(Date), expired, unavailable

        var permitsCleanup: Bool {
            switch self {
            case .unrestricted, .licensed, .trial: return true
            default: return false
            }
        }
    }

    static var configured: Bool { Bundle.main.object(forInfoDictionaryKey: "NukeLicensePublicKey") != nil }

    static var publicKey: Curve25519.Signing.PublicKey? {
        (Bundle.main.object(forInfoDictionaryKey: "NukeLicensePublicKey") as? String)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    static func status(now: Date = .now) -> Status {
        guard configured else { return .unrestricted }
        guard let publicKey else { return .invalidConfiguration }
        if let file = UserDefaults.standard.data(forKey: licenceKey),
           let licence = try? OfflineLicense.verify(file, key: publicKey, now: now) {
            return .licensed(licence.expiresAt)
        }
        var value: CFTypeRef?
        var request = trialQuery
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let result = SecItemCopyMatching(request as CFDictionary, &value)
        if result == errSecItemNotFound { return .notStarted }
        guard result == errSecSuccess, let data = value as? Data,
              let start = try? JSONDecoder().decode(Date.self, from: data) else { return .unavailable }
        return trialStatus(start: start, now: now)
    }

    static func trialStatus(start: Date, now: Date) -> Status {
        let end = start.addingTimeInterval(duration)
        return now >= start && now < end ? .trial(end) : .expired
    }

    static func start() -> Bool {
        guard status() == .notStarted, let data = try? JSONEncoder().encode(Date.now) else { return false }
        var request = trialQuery
        request[kSecValueData as String] = data
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }

    private static var trialQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.zyncraft.nukesweep.licensing",
            kSecAttrAccount as String: Bundle.main.bundleIdentifier ?? OfflineLicense.product,
        ]
    }
}
