import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

struct FolderGrant: Identifiable, Codable {
    let id: UUID
    let bookmark: Data
    let scoped: Bool
    let label: String
    let identity: FileIdentity
}
struct CleanupScope: Sendable {
    let root: URL
    let identity: FileIdentity
    var valid: Bool { root.resolvingSymlinksInPath().standardizedFileURL.path == root.standardizedFileURL.path && FileIdentity.read(root) == identity }
}
@MainActor final class FolderAccess: ObservableObject {
    static let shared = FolderAccess()
    @Published private(set) var grants: [FolderGrant] = []
    @Published private(set) var roots: [UUID: URL] = [:]
    @Published var note = "Choose a folder to inspect it and review cleanup of items inside it."
    var cleanupScopes: [CleanupScope] { grants.compactMap { grant in roots[grant.id].map { CleanupScope(root: $0, identity: grant.identity) } } }
    private var scopedRoots = Set<UUID>()
    init() {
        if let data = UserDefaults.standard.data(forKey: "nuke.folderBookmarks"), let saved = try? JSONDecoder().decode([FolderGrant].self, from: data) { grants = saved }
        restore()
    }
    func restore() {
        for id in scopedRoots { roots[id]?.stopAccessingSecurityScopedResource() }
        scopedRoots = []; roots = [:]
        var refreshed: [FolderGrant] = []
        for grant in grants {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: grant.bookmark, options: grant.scoped ? [.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
                if grant.scoped {
                    guard url.startAccessingSecurityScopedResource() else { refreshed.append(grant); continue }
                    scopedRoots.insert(grant.id)
                }
                roots[grant.id] = url
                if stale, let bookmark = try? url.bookmarkData(options: grant.scoped ? [.withSecurityScope] : [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    refreshed.append(.init(id: grant.id, bookmark: bookmark, scoped: grant.scoped, label: url.path, identity: grant.identity))
                } else { refreshed.append(grant) }
            } catch { refreshed.append(grant) }
        }
        grants = refreshed; persist()
    }
    @discardableResult func remember(_ url: URL) -> Bool {
        do {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard CleanupSafety.canGrant(canonical) else { note = "This broad or system location can be inspected, but cannot be added as a cleanup folder. Choose a specific folder in your home or on an external drive."; return false }
            if let old = grants.first(where: { roots[$0.id]?.standardizedFileURL == canonical || $0.label == canonical.path }) {
                if old.identity == FileIdentity.read(canonical), roots[old.id] != nil { return true }
                forget(old)
            }
            // The host is not sandboxed. Do not mistake a false scope result for denied filesystem access.
            let hasScope = url.startAccessingSecurityScopedResource()
            if hasScope { url.stopAccessingSecurityScopedResource() }
            let scopedData = hasScope ? try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) : nil
            let data = try scopedData ?? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
            guard let identity = FileIdentity.read(canonical) else { note = "Could not verify the selected folder. Choose it again."; return false }
            let grant = FolderGrant(id: UUID(), bookmark: data, scoped: scopedData != nil, label: canonical.path, identity: identity)
            grants.append(grant); restore()
            note = "Folder remembered. macOS privacy settings and filesystem permissions still apply. No files were selected or removed."
            return true
        } catch { note = "Could not remember folder access: " + error.localizedDescription; return false }
    }
    func forget(_ grant: FolderGrant) {
        if scopedRoots.remove(grant.id) != nil { roots[grant.id]?.stopAccessingSecurityScopedResource() }
        roots[grant.id] = nil; grants.removeAll { $0.id == grant.id }; persist()
        note = "Folder forgotten. This removes Nuke Sweep’s saved access; it does not change macOS privacy settings."
    }
    func persist() { if let data = try? JSONEncoder().encode(grants) { UserDefaults.standard.set(data, forKey: "nuke.folderBookmarks") } }
}
@MainActor final class PermissionSettings: ObservableObject {
    @Published var notifications = "Not checked"
    @Published var loginStatus = "Not checked"
    @Published var loginEnabled = false
    @Published var note = ""
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "Enabled"; loginEnabled = true
        case .requiresApproval: loginStatus = "Awaiting approval in Login Items"; loginEnabled = false
        case .notRegistered: loginStatus = "Off"; loginEnabled = false
        case .notFound: loginStatus = "Unavailable for this app location"; loginEnabled = false
        @unknown default: loginStatus = "Unknown"; loginEnabled = false
        }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized: notifications = "Allowed"
            case .denied: notifications = "Denied — change in Notifications settings"
            case .notDetermined: notifications = "Not requested"
            case .provisional: notifications = "Provisional"
            case .ephemeral: notifications = "Temporary"
            @unknown default: notifications = "Unknown"
            }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; note = "" }
        catch { note = "Could not change login registration: " + error.localizedDescription }
        refresh()
    }
    static func openPrivacy() { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) } }
    static func openNotifications() { if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) } }
}
struct PermissionsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var access = FolderAccess.shared
    @StateObject private var settings = PermissionSettings()
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let recovery = model.recovery {
                Notice(text: "Retry the blocked inspection: " + recovery.title + ". Choose the relevant access below, then retry. macOS may require restarting Nuke Sweep after a Full Disk Access change.", symbol: "hand.raised")
                Button("Choose folder for this inspection…") { model.chooseFolderForRecovery() }.buttonStyle(QuietButton())
                Button("Retry this inspection") { model.retryRecovery() }.buttonStyle(PrimaryButton())
            }
            SectionTitle(title: "Folder access", detail: "Choose only the locations you need")
            Text("Nuke Sweep runs without administrator privileges. Choosing a folder uses macOS’s file picker; saved bookmarks remember that choice. Files still need a cleanup review. The chosen root itself and system locations are protected.").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: 720, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack { Button("Choose a folder…") { model.chooseFolder() }.buttonStyle(PrimaryButton()); Button("Retry saved access") { access.restore(); settings.refresh() }.buttonStyle(QuietButton()) }
            Text(access.note).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            ForEach(access.grants) { grant in
                HStack {
                    VStack(alignment: .leading, spacing: 4) { Text(access.roots[grant.id]?.path ?? grant.label).textSelection(.enabled); Text(access.roots[grant.id] == nil ? "Access unavailable — choose the folder again" : "Bookmark resolved · filesystem/privacy checks still apply").foregroundStyle(access.roots[grant.id] == nil ? Theme.warning : Theme.secondary) }.font(.system(size: 11))
                    Spacer(); Button("Forget") { access.forget(grant) }.buttonStyle(QuietButton())
                }; Divider()
            }
            SectionTitle(title: "Protected folders", detail: "Full Disk Access is controlled by macOS")
            Text("Trash, some app data, and backups can require Full Disk Access. Nuke Sweep cannot grant it or reliably report one global permission status. Full Disk Access does not override filesystem ownership or make a read-only volume writable. A partial scan is not an empty folder. If a scan reports denied access, open Settings, add this Nuke Sweep build, then retry the scan. macOS may require quitting and reopening Nuke Sweep.").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: 720, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack { Button("Open Full Disk Access settings") { PermissionSettings.openPrivacy() }.buttonStyle(QuietButton()); Button("Reveal this Nuke Sweep build") { model.reveal(Bundle.main.bundleURL) }.buttonStyle(QuietButton()) }
            SectionTitle(title: "Notifications and startup", detail: "Optional")
            Text("Notifications: " + settings.notifications).font(.system(size: 12))
            Button("Open Notifications settings") { PermissionSettings.openNotifications() }.buttonStyle(QuietButton())
            Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(QuietButton())
            Toggle("Launch Nuke Sweep at login", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLogin($0) })).font(.system(size: 12))
            Text("Login item: " + settings.loginStatus).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if !settings.note.isEmpty { Notice(text: settings.note, symbol: "info.circle") }
            Button("Refresh permission status") { settings.refresh() }.buttonStyle(QuietButton())
            Notice(text: "No Accessibility, Screen Recording, administrator helper, or automatic deletion is required. Permission to read a folder is not permission to remove it. Forgetting a bookmark does not revoke access already granted in System Settings.", symbol: "hand.raised")
        }.onAppear { settings.refresh() }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refresh() }
    }
}
struct AccessRecovery: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack {
            if model.page == .trash { Button("Retry Trash scan") { model.inspectTrash() }.buttonStyle(QuietButton()).disabled(model.trashLoading) }
            else { Button("Choose folder again…") { model.chooseFolder() }.buttonStyle(QuietButton()) }
            Button("Resolve access for this inspection") { model.prepareRecovery(model.page == .trash ? .trash : .storage(model.scanRoot)) }.buttonStyle(QuietButton())
        }
    }
}
