import CryptoKit
import XCTest
@testable import Nuke

final class OfflineLicenseTests: XCTestCase {
    func testTrialExpiresAtFourteenDays() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(14 * 86_400)
        XCTAssertEqual(TrialAccess.trialStatus(start: start, now: start), .trial(end))
        XCTAssertTrue(TrialAccess.trialStatus(start: start, now: end.addingTimeInterval(-1)).permitsCleanup)
        XCTAssertFalse(TrialAccess.trialStatus(start: start, now: end).permitsCleanup)
        XCTAssertFalse(TrialAccess.trialStatus(start: start, now: start.addingTimeInterval(-1)).permitsCleanup)
    }

    func testSignedFileVerifiesOfflineAndRejectsModifiedPayload() throws {
        let key = Curve25519.Signing.PrivateKey()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let license = OfflineLicense(schema: 1, product: OfflineLicense.product, id: UUID(),
                                     issuedAt: date, expiresAt: date.addingTimeInterval(60))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(license)
        let signature = try key.signature(for: payload)
        let file = try encoder.encode(OfflineLicense.Envelope(payload: payload, signature: signature))
        XCTAssertEqual(try OfflineLicense.verify(file, key: key.publicKey, now: date), license)
        XCTAssertThrowsError(try OfflineLicense.verify(file, key: key.publicKey, now: date.addingTimeInterval(60))) {
            XCTAssertEqual($0 as? OfflineLicense.ValidationError, .expired)
        }
        XCTAssertThrowsError(try OfflineLicense.verify(file, key: Curve25519.Signing.PrivateKey().publicKey, now: date)) {
            XCTAssertEqual($0 as? OfflineLicense.ValidationError, .invalidSignature)
        }

        let edited = OfflineLicense(schema: 1, product: OfflineLicense.product, id: license.id,
                                    issuedAt: date, expiresAt: nil)
        let tampered = try encoder.encode(OfflineLicense.Envelope(payload: encoder.encode(edited), signature: signature))
        XCTAssertThrowsError(try OfflineLicense.verify(tampered, key: key.publicKey, now: date)) {
            XCTAssertEqual($0 as? OfflineLicense.ValidationError, .invalidSignature)
        }
    }
}
