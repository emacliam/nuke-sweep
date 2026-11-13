import SwiftUI
import AppKit

struct DeveloperScopesSection: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var editing: DeveloperScope?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Custom scopes").font(.system(size: 15, weight: .semibold))
                Text("Remembered folders with their own exclusions").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                Spacer(minLength: 8)
                if !features.developerScopes.isEmpty {
                    Button("Measure all") { features.measureAllDeveloperScopes() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        .disabled(!features.measuringScopes.isEmpty)
                }
                Menu {
                    ForEach(DeveloperScopePreset.all) { preset in
                        Button(preset.title) { editing = preset.scope }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 10))
                        Text("Presets")
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Start with exclusions for a common project type")
                Menu {
                    Button("Export scopes…") { features.exportDeveloperScopes() }.disabled(features.developerScopes.isEmpty)
                    Button("Import scopes…") { features.importDeveloperScopes() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Export or import scope definitions")
                Button("Add scope…") {
                    editing = DeveloperScope(label: "", path: "", cleanupAllowed: false, exclusions: [])
                }.buttonStyle(QuietButton())
            }
            if let status = features.scopeStatus {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    Text(status).font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { features.scopeStatus = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary) }.buttonStyle(.plain).accessibilityLabel("Dismiss scope message")
                }
            }
            if features.developerScopes.isEmpty {
                Surface {
                    HStack(spacing: 14) {
                        Image(systemName: "folder.badge.gearshape").font(.system(size: 22)).foregroundStyle(Theme.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Remember a folder you clean often").font(.system(size: 13, weight: .semibold))
                            Text("A project, build folder, or package cache. Nuke Sweep measures it here, skips paths you exclude, and sends cleanup through the same review.")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            } else {
                ForEach(features.developerScopes) { scope in
                    ScopeCard(scope: scope, onEdit: { editing = $0 })
                }
            }
        }
        .sheet(item: $editing) { scope in
            ScopeEditor(scope: scope) { saved in
                features.upsertDeveloperScope(saved)
                features.measureDeveloperScope(saved)
            }
        }
    }
}

private struct ScopeCard: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @ObservedObject private var access = FolderAccess.shared
    let scope: DeveloperScope
    var onEdit: (DeveloperScope) -> Void
    @State private var expanded = false
    @State private var selection: [String: DiskItem] = [:]
    @State private var tree = FolderTreeStore()

    private var measurement: ScopeMeasurement? { features.scopeMeasurements[scope.id] }
    private var measuring: Bool { features.measuringScopes.contains(scope.id) }
    private var prettyPath: String { scope.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") }
    private var covered: Bool {
        let path = scope.url.standardizedFileURL.path
        return access.cleanupScopes.contains { grant in
            path == grant.root.standardizedFileURL.path || path.hasPrefix(grant.root.standardizedFileURL.path + "/")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: scope.cleanupAllowed ? "folder.badge.gearshape" : "folder")
                    .font(.system(size: 14)).foregroundStyle(Theme.orange).frame(width: 20)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(scope.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(scope.cleanupAllowed ? "Cleanup" : "Inspect only")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(scope.cleanupAllowed ? Theme.green : Theme.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background((scope.cleanupAllowed ? Theme.green : Theme.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(prettyPath).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                }
                .contentShape(Rectangle())
                .onTapGesture { expanded.toggle() }
                Spacer(minLength: 12)
                if measuring { ProgressView().controlSize(.mini) }
                else if let measurement {
                    Text(measurement.unavailable ? "Unavailable" : bytes(measurement.size) + (measurement.incomplete ? "+" : ""))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(measurement.unavailable ? Theme.warning : Theme.ink)
                } else { Text("Not measured").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Menu {
                    Button("Measure now") { features.measureDeveloperScope(scope) }.disabled(measuring)
                    Button("Edit scope…") { onEdit(scope) }
                    Button("Reveal in Finder") { model.reveal(scope.url) }
                    Divider()
                    Button("Forget scope", role: .destructive) { features.removeDeveloperScope(scope.id) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 22, height: 20).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Scope actions")
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 16)
                }.buttonStyle(.plain).accessibilityLabel(expanded ? "Hide scope details" : "Show scope details")
            }
            .padding(12)

            if expanded { details }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
        // The scope is captured by value rather than passing a bound method
        // reference, so the predicate is provably Sendable for the disk lanes.
        .onAppear { let current = scope; tree.configure { current.isExcluded($0) } }
        .onChange(of: scope) { _, updated in tree.configure { updated.isExcluded($0) } }
        .onChange(of: measurement?.measured) { _, _ in tree.reset(); selection = [:] }
        .onChange(of: model.finishedReceipt?.id) { _, _ in tree.reset(); selection = [:] }
    }

    private func applyExclusions(_ items: [DiskItem]) {
        let updated = DeveloperScope.applyingPlanExclusions(root: scope.url, existing: scope, additions: items.map(\.url))
        guard updated.exclusions != scope.exclusions else { return }
        features.upsertDeveloperScope(updated)
        features.measureDeveloperScope(updated)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.line)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(scope.exclusions.isEmpty ? "No exclusions — every item is selectable after review." : "Excluded: " + scope.exclusions.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if scope.cleanupAllowed && !covered {
                    Label("Access not granted", systemImage: "hand.raised").font(.system(size: 10)).foregroundStyle(Theme.warning)
                    Button("Review access") { model.page = .permissions }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                }
            }
            if measuring {
                Text("Measuring this scope…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else if let measurement {
                if measurement.unavailable {
                    Notice(text: "This folder is missing or unreadable. Edit the scope or restore access.", symbol: "exclamationmark.triangle")
                } else if measurement.items.isEmpty {
                    Text("No items measured in this folder.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                } else {
                    FolderTreeView(
                        store: tree,
                        selection: $selection,
                        items: measurement.items,
                        selectionEnabled: scope.cleanupAllowed,
                        blocked: { scope.blocksSelection($0) },
                        scope: scope,
                        onApplyExclusions: applyExclusions,
                        hint: "Excluded paths are skipped; a folder containing one cannot be selected. Project-looking folders are refused at review."
                    ).frame(height: 280)
                    if measurement.limited || measurement.skipped > 0 {
                        Text("Partial measurement — some locations were skipped. Review still rechecks the selected items.")
                            .font(.system(size: 10)).foregroundStyle(Theme.warning)
                    }
                    if scope.cleanupAllowed {
                        HStack(spacing: 8) {
                            Text("\(selection.count) selected").font(.system(size: 11))
                            Spacer()
                            Button("Add to basket") { model.addToBasket(Array(selection.values)) }.buttonStyle(QuietButton()).disabled(selection.isEmpty || model.actionBusy || measuring || !covered)
                            Button("Review selected…") { model.reviewTrash(Array(selection.values)) }
                                .buttonStyle(PrimaryButton())
                                .disabled(selection.isEmpty || model.actionBusy || measuring || !covered)
                        }
                    } else {
                        Text("Inspect only. Enable cleanup in Edit scope to select items.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                Text("Not measured yet. Use Measure now in the scope menu.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

}

private struct ScopeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope: DeveloperScope
    @State private var exclusionsText = ""
    @State private var error = ""
    var onSave: (DeveloperScope) -> Void

    init(scope: DeveloperScope, onSave: @escaping (DeveloperScope) -> Void) {
        _scope = State(initialValue: scope)
        _exclusionsText = State(initialValue: scope.exclusions.joined(separator: "\n"))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(scope.label.isEmpty && scope.path.isEmpty ? "Add custom scope" : "Edit custom scope", systemImage: "folder.badge.gearshape")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 7) {
                Text("Folder").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                HStack(spacing: 10) {
                    Text(scope.path.isEmpty ? "No folder chosen" : scope.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(scope.path.isEmpty ? Theme.secondary : Theme.ink)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose folder…") { chooseFolder() }.buttonStyle(QuietButton())
                }
            }
            TextField("Label", text: $scope.label).textFieldStyle(.roundedBorder).font(.system(size: 12))
            Toggle("Allow cleanup after review", isOn: $scope.cleanupAllowed).font(.system(size: 12))
            Text("Nuke Sweep cannot classify an arbitrary folder. Prefer build or cache folders; source-looking folders are refused at review. Cleanup still requires the review sheet and a macOS folder grant. Turning this off keeps the scope inspect-only; adding or forgetting a scope never touches files.")
                .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                Text("Excluded paths").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                TextEditor(text: $exclusionsText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 72)
                    .padding(6)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
                Text("One relative path per line or comma-separated, for example node_modules or packages/web/build. Excluded paths are not measured, and a folder containing one cannot be selected. Wildcards are not supported.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(Theme.error).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save scope") { save() }.buttonStyle(PrimaryButton()).disabled(scope.path.isEmpty)
            }
        }
        .padding(26)
        .frame(width: 560)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use folder"
        if panel.runModal() == .OK, let url = panel.url {
            let standardized = url.resolvingSymlinksInPath().standardizedFileURL
            scope.path = standardized.path
            if scope.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { scope.label = standardized.lastPathComponent }
            error = ""
        }
    }

    private func save() {
        let url = URL(fileURLWithPath: scope.path).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            error = "Choose an existing folder."
            return
        }
        var saved = scope
        saved.path = url.path
        let trimmed = scope.label.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.label = trimmed.isEmpty ? url.lastPathComponent : trimmed
        saved.exclusions = DeveloperScope.normalizeExclusions(exclusionsText, root: url)
        if saved.cleanupAllowed && !FolderAccess.shared.remember(url) {
            saved.cleanupAllowed = false
            scope.cleanupAllowed = false
            error = "Cleanup access could not be granted for this folder. Choose a narrower folder, or save it as inspect-only."
            return
        }
        onSave(saved)
        dismiss()
    }
}
