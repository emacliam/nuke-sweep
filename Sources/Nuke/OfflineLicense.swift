import CryptoKit
import Foundation

struct OfflineLicense: Codable, Equatable {
    static let product = "com.zyncraft.nukesweep"

    let schema: Int
    let product: String
    let id: UUID
    let issuedAt: Date
    let expiresAt: Date?

    struct Envelope: Codable {
        let payload: Data
        let signature: Data
    }

    enum ValidationError: LocalizedError {
        case invalidFile, invalidSignature, wrongProduct, notYetValid, expired

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "The licence file could not be read."
            case .invalidSignature: return "The licence signature could not be verified."
            case .wrongProduct: return "This licence is for a different product or format."
            case .notYetValid: return "This licence is not valid yet. Check your Mac’s date and time."
            case .expired: return "This licence has expired."
            }
        }
    }

    static func verify(_ file: Data, key: Curve25519.Signing.PublicKey, now: Date = .now) throws -> Self {
        guard file.count <= 16_384,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: file),
              envelope.signature.count == 64 else { throw ValidationError.invalidFile }
        guard key.isValidSignature(envelope.signature, for: envelope.payload) else {
            throw ValidationError.invalidSignature
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let license = try? decoder.decode(Self.self, from: envelope.payload),
              license.expiresAt.map({ $0 > license.issuedAt }) ?? true else {
            throw ValidationError.invalidFile
        }
        guard license.schema == 1, license.product == product else { throw ValidationError.wrongProduct }
        guard now >= license.issuedAt else { throw ValidationError.notYetValid }
        if let expiration = license.expiresAt, now >= expiration { throw ValidationError.expired }
        return license
    }
}
