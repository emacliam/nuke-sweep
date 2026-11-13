import SwiftUI
import Darwin

/// Whether this build appears to have Full Disk Access.
///
/// macOS offers no API for this. The accepted probe is to try opening a file the
/// system only lets a process read when the permission is granted. It is a
/// strong signal, not a guarantee, so the result is described as "appears" and a
/// probe that cannot decide says so rather than guessing.
enum DiskAccessProbe {
    enum Status: Equatable, Sendable { case granted, missing, unknown }

    static func status(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Status {
        // The user's privacy database exists on every account and is protected.
        // A folder that is always protected is the fallback when it is absent.
        let probes = [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
            home.appendingPathComponent("Library/Safari/Bookmarks.plist").path,
        ]
        var sawDenial = false
        for path in probes {
            let descriptor = open(path, O_RDONLY | O_NONBLOCK)
            if descriptor >= 0 { close(descriptor); return .granted }
            if errno == EPERM || errno == EACCES { sawDenial = true }
        }
        return sawDenial ? .missing : .unknown
    }
}

/// Shown before the first check when Full Disk Access appears to be missing.
///
/// Without it the check still runs, but Trash and some application data read as
/// empty or partial, so the first answer a new user sees is quietly too small.
/// Saying so up front, with the three steps to fix it, is better than leaving a
/// partial result to explain itself afterwards.
struct AccessStep: View {
    @Environment(AppModel.self) var model
    /// True when shown under a finished result rather than before the first check.
    var afterCheck = false

    var body: some View {
        if afterCheck { compact } else { walkthrough }
    }

    /// Under a finished result the answer comes first; this is one line and a
    /// button, not a second card competing with the figures.
    private var compact: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "lock.shield").font(.system(size: 11)).foregroundStyle(Theme.warning)
            Text("These figures are a lower bound: macOS kept Trash and some application data private.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Allow Full Disk Access…") { PermissionSettings.openPrivacy() }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                .help("Opens System Settings. Switch on Nuke Sweep there, then check again. Reading is all this allows.")
        }
    }

    private var walkthrough: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield").font(.system(size: 13)).foregroundStyle(Theme.warning).frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text("One thing first: Nuke Sweep cannot see everything yet")
                        .font(.system(size: 12, weight: .semibold))
                    Text("macOS keeps Trash and some application data private until you allow it. The check works without it, but its total will be too small.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                numbered(1, "Open Full Disk Access in System Settings.")
                numbered(2, "Switch on Nuke Sweep. If it is not listed, press + and choose it.")
                numbered(3, "Come back here. macOS may ask to quit and reopen Nuke Sweep.")
            }
            .padding(.leading, 25)
            HStack(spacing: 10) {
                Button("Open Full Disk Access settings") { PermissionSettings.openPrivacy() }.buttonStyle(QuietButton())
                Button("Show Nuke Sweep in Finder") { model.reveal(Bundle.main.bundleURL) }.buttonStyle(QuietButton())
                    .help("Useful for step 2 if the app is not in the list")
                Spacer()
            }
            .padding(.leading, 25)
            Text("Reading is all this allows. It does not let Nuke Sweep remove anything without a review.")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).padding(.leading, 25)
        }
        .padding(12)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func numbered(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(verbatim: "\(number).").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
