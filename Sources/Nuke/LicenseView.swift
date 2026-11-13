import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct LicenseView: View {
    @AppStorage(TrialAccess.licenceKey) private var installed: Data?
    @State private var importing = false
    @State private var message: String?

    @State private var status = TrialAccess.status()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Licence").font(.system(size: 18, weight: .semibold))
            switch status {
            case .licensed(let expiration):
                if let expiration { Text("Licence valid until \(expiration.formatted(date: .abbreviated, time: .shortened))") }
                else { Text("Lifetime licence active") }
            case .trial(let expiration):
                Text("Trial ends \(expiration.formatted(date: .abbreviated, time: .shortened))")
            case .notStarted:
                Text("Try cleanup free for 14 days. Scans and restore stay available after the trial.")
                Button("Start 14-day trial") {
                    if !TrialAccess.start() { message = "Could not start the trial. Check that your login Keychain is available." }
                    status = TrialAccess.status()
                }.buttonStyle(PrimaryButton())
            case .expired:
                Text("Your trial has ended. Import a licence to resume cleanup.")
            case .unavailable:
                Text("The trial could not be read from Keychain.")
            case .invalidConfiguration, .unrestricted:
                Text("Licence activation is unavailable in this build.")
            }
            if TrialAccess.publicKey != nil {
                Button("Import licence file…") { importing = true }.buttonStyle(QuietButton())
            }
            if let message { Notice.measured(message, symbol: "exclamationmark.triangle") }
        }
        .onAppear { status = TrialAccess.status() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard let key = TrialAccess.publicKey else { return }
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: 16_385) ?? Data()
                _ = try OfflineLicense.verify(data, key: key)
                installed = data
                status = TrialAccess.status()
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
