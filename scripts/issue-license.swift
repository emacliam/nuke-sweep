import CryptoKit
import Foundation

// Compile alongside Sources/Nuke/OfflineLicense.swift. The private seed comes
// from stdin so it does not appear in process arguments or shell history.
@main enum IssueLicense {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 || arguments.count == 2,
              let seedLine = readLine(),
              let seed = Data(base64Encoded: seedLine) else {
            throw Usage.invalid
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        if arguments == ["public-key"] {
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        guard let id = UUID(uuidString: arguments[0]) else { throw Usage.invalid }
        let now = Date()
        let expiration: Date?
        if arguments.count == 2 {
            guard let days = Int(arguments[1]), (1...3650).contains(days) else { throw Usage.invalid }
            expiration = now.addingTimeInterval(Double(days) * 86_400)
        } else {
            expiration = nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let licence = OfflineLicense(schema: 1, product: OfflineLicense.product, id: id,
                                     issuedAt: now, expiresAt: expiration)
        let payload = try encoder.encode(licence)
        let file = try encoder.encode(OfflineLicense.Envelope(payload: payload, signature: key.signature(for: payload)))
        FileHandle.standardOutput.write(file)
    }

    private enum Usage: LocalizedError {
        case invalid
        var errorDescription: String? {
            "Use public-key or LICENCE_UUID [VALID_DAYS]. Supply the base64 Ed25519 seed on stdin."
        }
    }
}
