import SwiftUI
import AppKit

/// Keeps a tree selection unambiguous: an ancestor and its descendants are never
/// reviewed together, so one cleanup cannot count or move the same bytes twice.
enum TreeSelection {
    static func updated(_ current: [String: DiskItem], toggling item: DiskItem, on: Bool) -> [String: DiskItem] {
        guard on else {
            var next = current
            next[item.url.path] = nil
            return next
        }
        let path = item.url.path
        var next = current.filter { key, _ in
            key != path && !key.hasPrefix(path + "/") && !path.hasPrefix(key + "/")
        }
        next[path] = item
        return next
    }
}

/// Lazily measures one level of a folder at a time. The main scan already supplies the
/// first level; deeper levels are measured only when a disclosure is opened.
@MainActor final class FolderTreeStore: ObservableObject {
    @Published private(set) var children: [String: [DiskItem]] = [:]
    @Published private(set) var expanded = Set<String>()
    @Published private(set) var loading = Set<String>()
    @Published private(set) var partial = Set<String>()
    private var isExcluded: (URL) -> Bool = { _ in false }
    private var tokens: [String: ScanCancellation] = [:]
    private var evidenceCache: [String: CleanupEvidence] = [:]

    func evidence(for item: DiskItem, sourceCheck: Bool) -> CleanupEvidence {
        let key = item.id + (sourceCheck ? "|source" : "")
        if let cached = evidenceCache[key] { return cached }
        let evidence = CleanupEvidenceService.classify(item.url, sourceCheck: sourceCheck)
        evidenceCache[key] = evidence
        return evidence
    }

    func configure(isExcluded: @escaping (URL) -> Bool) {
        self.isExcluded = isExcluded
        reset()
    }

    func isFolder(_ item: DiskItem) -> Bool { item.directory && !item.symlink }

    func toggle(_ item: DiskItem) {
        guard isFolder(item) else { return }
        if expanded.contains(item.id) {
            expanded.remove(item.id)
            tokens[item.id]?.cancel()
            tokens[item.id] = nil
            loading.remove(item.id)
            return
        }
        expanded.insert(item.id)
        guard children[item.id] == nil, !loading.contains(item.id) else { return }
        loading.insert(item.id)
        partial.remove(item.id)
        let token = ScanCancellation()
        tokens[item.id] = token
        let excluded = isExcluded
        Task {
            let result = await DiskWork.run("Inspecting \(item.name)", cancellation: token) {
                DiskScanner.scan(item.url, cancellation: token, limit: 12_000, deadline: Date().addingTimeInterval(6), excluding: excluded)
            }
            guard tokens[item.id] === token else { return }
            tokens[item.id] = nil
            loading.remove(item.id)
            children[item.id] = result.items
            if result.limited || result.skipped > 0 || token.cancelled { partial.insert(item.id) }
        }
    }

    func reset() {
        for token in tokens.values { token.cancel() }
        tokens.removeAll(); children.removeAll(); expanded.removeAll(); loading.removeAll(); partial.removeAll(); evidenceCache.removeAll()
    }

    func collapseAll() {
        for token in tokens.values { token.cancel() }
        tokens.removeAll(); expanded.removeAll(); loading.removeAll()
    }
}

struct TreeRowData: Identifiable {
    let item: DiskItem
    let depth: Int
    let evidence: CleanupEvidence
    var expanded = false
    var loading = false
    var partial = false
    var empty = false
    var blocked = false
    var id: String { item.id }
}

/// Files tree mode. Sizes come from the measured scan; selecting a folder selects its
/// whole current subtree at review time, and the review sheet rechecks identities.
struct FolderTreeView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: FolderTreeStore
    @Binding var selection: [String: DiskItem]
    let items: [DiskItem]
    var selectionEnabled = true
    var blocked: (DiskItem) -> Bool = { _ in false }
    var hint = "Expand a folder to inspect it. Selecting a folder includes its contents at review."

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(hint).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                Spacer()
                if !store.expanded.isEmpty { Button("Collapse all") { store.collapseAll() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Theme.line)
            if rows.isEmpty {
                Text("No items measured in this folder.").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            TreeRowView(row: row, store: store, selection: $selection, selectionEnabled: selectionEnabled)
                            Divider().overlay(Theme.line).padding(.leading, 24 + CGFloat(row.depth) * 14)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
    }

    private var rows: [TreeRowData] {
        var out: [TreeRowData] = []
        append(items, depth: 0, into: &out)
        return out
    }

    private func append(_ items: [DiskItem], depth: Int, into out: inout [TreeRowData]) {
        for item in items {
            let expanded = store.expanded.contains(item.id)
            let loading = store.loading.contains(item.id)
            let kids = store.children[item.id]
            let evidence = store.evidence(for: item, sourceCheck: depth == 0)
            out.append(TreeRowData(
                item: item,
                depth: depth,
                evidence: evidence,
                expanded: expanded,
                loading: loading,
                partial: store.partial.contains(item.id),
                empty: expanded && !loading && kids?.isEmpty == true,
                blocked: blocked(item) || evidence.kind.isBlocked
            ))
            if expanded, let kids { append(kids, depth: depth + 1, into: &out) }
        }
    }
}

private struct TreeRowView: View {
    @EnvironmentObject var model: AppModel
    let row: TreeRowData
    @ObservedObject var store: FolderTreeStore
    @Binding var selection: [String: DiskItem]
    let selectionEnabled: Bool
    @State private var hovered = false
    private var folder: Bool { row.item.directory && !row.item.symlink }

    var body: some View {
        HStack(spacing: 7) {
            Button { store.toggle(row.item) } label: {
                Image(systemName: row.expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(folder ? 1 : 0)
            .disabled(!folder)
            .accessibilityLabel(row.expanded ? "Collapse \(row.item.name)" : "Expand \(row.item.name)")

            Toggle("Select \(row.item.name)", isOn: Binding(
                get: { selection[row.item.id] != nil },
                set: { selection = TreeSelection.updated(selection, toggling: row.item, on: $0) }
            ))
            .labelsHidden().toggleStyle(.checkbox)
            .disabled(!selectionEnabled || row.blocked || row.item.incomplete || model.actionBusy || model.scanning)

            Image(systemName: row.item.symlink ? "link" : row.item.directory ? "folder.fill" : "doc")
                .font(.system(size: 12)).foregroundStyle(row.item.directory ? Theme.orange : Theme.secondary).frame(width: 16)
            Text(row.item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            if row.evidence.kind != .unknown {
                Text(row.evidence.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(row.evidence.kind.isBlocked ? Theme.warning : row.evidence.kind == .knownCache ? Theme.green : Theme.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background((row.evidence.kind.isBlocked ? Theme.warning : Theme.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    .help(row.evidence.detail + (row.evidence.rebuild.map { " " + $0 } ?? ""))
            }
            if row.loading { ProgressView().controlSize(.mini) }
            if row.blocked { Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(Theme.warning).help("This folder cannot be selected: it contains an excluded path or looks like a project/source root. Expand it to pick safe items.") }
            else if row.partial { Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(Theme.warning).help("Only part of this folder could be inspected. Review still rechecks every item.") }
            if row.empty { Text("Empty").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            Spacer(minLength: 12)
            Text(bytes(row.item.size) + (row.item.incomplete || row.partial ? "+" : ""))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .padding(.leading, 12 + CGFloat(row.depth) * 14)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(hovered ? Theme.rail.opacity(0.45) : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { if folder { store.toggle(row.item) } }
        .accessibilityElement(children: .contain)
    }
}
