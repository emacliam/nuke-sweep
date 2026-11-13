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
@Observable @MainActor final class FolderTreeStore {
    private(set) var children: [String: [DiskItem]] = [:]
    private(set) var expanded = Set<String>()
    private(set) var loading = Set<String>()
    private(set) var partial = Set<String>()
    // @Sendable because the tree hands this predicate to the disk lanes.
    // The only caller passes `DeveloperScope.isExcluded`, and a scope is a
    // Sendable value, so nothing MainActor-isolated is captured.
    private var isExcluded: @Sendable (URL) -> Bool = { _ in false }
    private var tokens: [String: ScanCancellation] = [:]
    private var evidenceCache: [String: CleanupEvidence] = [:]

    private var evidencePending: [String: (DiskItem, Bool)] = [:]
    private var evidenceGeneration = UUID()
    private var evidenceWorker: Task<Void, Never>?
    private var evidenceToken = ScanCancellation()

    func evidence(for item: DiskItem, sourceCheck: Bool) -> CleanupEvidence {
        evidenceCache[item.id + (sourceCheck ? "|source" : "")] ?? CleanupEvidence(kind: .unknown, detail: "Checking folder context…", rebuild: nil, gitIgnored: false)
    }
    /// Requested by visible rows only, not while flattening every expanded node.
    func requestEvidence(_ item: DiskItem, sourceCheck: Bool) {
        let key = item.id + (sourceCheck ? "|source" : "")
        guard evidenceCache[key] == nil else { return }
        evidencePending[key] = (item, sourceCheck)
        guard evidenceWorker == nil else { return }
        if evidenceToken.cancelled { evidenceToken = ScanCancellation() }
        let generation = evidenceGeneration, token = evidenceToken
        evidenceWorker = Task {
            while !evidencePending.isEmpty, !token.cancelled {
                let batch = Array(evidencePending.prefix(16))
                let updates = await DiskWork.run("Inspecting visible folder context", priority: .background, cancellation: token) { () -> [String: CleanupEvidence] in
                    let deadline = Date().addingTimeInterval(2)
                    var updates: [String: CleanupEvidence] = [:]
                    for (key, value) in batch {
                        guard !token.cancelled, Date() < deadline else { break }
                        updates[key] = CleanupEvidenceService.classify(value.0.url, sourceCheck: value.1)
                    }
                    return updates
                }
                guard evidenceGeneration == generation else { return }
                for key in updates.keys { evidencePending[key] = nil }
                evidenceCache.merge(updates) { _, new in new }
                if updates.isEmpty { break }
            }
            if evidenceGeneration == generation { evidenceWorker = nil }
        }
    }
    func evidenceReady(for item: DiskItem, sourceCheck: Bool) -> Bool {
        evidenceCache[item.id + (sourceCheck ? "|source" : "")] != nil
    }

    func configure(isExcluded: @escaping @Sendable (URL) -> Bool) {
        self.isExcluded = isExcluded
        reset()
    }

    func isFolder(_ item: DiskItem) -> Bool { item.directory && !item.symlink }

    func toggle(_ item: DiskItem) {
        guard isFolder(item) else { return }
        if expanded.contains(item.id) {
            expanded.remove(item.id)
            let descendants = tokens.keys.filter { $0 == item.id || $0.hasPrefix(item.id + "/") }
            for key in descendants { tokens[key]?.cancel(); tokens[key] = nil; loading.remove(key) }
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
            UIResponsiveness.mark(.treeListingQueued)
            let result = await DiskWork.run("Listing \(item.name)", lane: .interactive, cancellation: token) {
                FolderListing.inspect(item.url, token: token, excluding: excluded)
            }
            guard tokens[item.id] === token else { return }
            loading.remove(item.id)
            children[item.id] = result.items
            UIResponsiveness.mark(.treeListingPublished)
            if result.limited || result.skipped > 0 { partial.insert(item.id) }
            guard !token.cancelled else { tokens[item.id] = nil; return }
            let measured = await DiskWork.run("Measuring \(item.name)", priority: .background, cancellation: token) {
                FolderListing.measure(result.items, token: token, excluding: excluded)
            }
            guard tokens[item.id] === token else { return }
            tokens[item.id] = nil
            // Preserve a newer explicit measurement completed while this batch
            // was queued. A background pass must not restore stale sizes.
            let current = Dictionary(uniqueKeysWithValues: (children[item.id] ?? []).map { ($0.id, $0) })
            children[item.id] = measured.map { candidate in
                if let fresh = current[candidate.id], fresh.measurementPending == false { return fresh }
                return candidate
            }
        }
    }

    func measure(_ item: DiskItem) {
        guard item.directory, !item.symlink, !loading.contains(item.id) else { return }
        let token = ScanCancellation(), excluded = isExcluded
        tokens[item.id]?.cancel(); tokens[item.id] = token; loading.insert(item.id)
        Task {
            let result = await DiskWork.run("Measuring \(item.name)", cancellation: token) { FolderListing.measure([item], token: token, excluding: excluded) }
            guard tokens[item.id] === token else { return }
            tokens[item.id] = nil; loading.remove(item.id)
            let parent = item.url.deletingLastPathComponent().path
            if let index = children[parent]?.firstIndex(where: { $0.id == item.id }), let measured = result.first { children[parent]?[index] = measured }
        }
    }

    func cancelPendingWork() {
        for token in tokens.values { token.cancel() }
        tokens.removeAll(); loading.removeAll()
        evidenceToken.cancel(); evidenceWorker?.cancel(); evidenceWorker = nil
        evidenceToken = ScanCancellation(); evidencePending.removeAll(); evidenceGeneration = UUID()
    }
    func reset() {
        cancelPendingWork()
        children.removeAll(); expanded.removeAll(); partial.removeAll(); evidenceCache.removeAll()
    }
    func collapseAll() {
        cancelPendingWork(); expanded.removeAll()
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
    var checking = false
    var id: String { item.id }
}

/// A structural snapshot. Evidence and selection do not change row order.
struct FolderOutlineInput: Equatable {
    let roots: [DiskItem]
    let children: [String: [DiskItem]]
    let expanded: Set<String>
}

struct FolderOutline {
    struct Entry: Identifiable {
        let item: DiskItem
        let depth: Int
        let parentID: String?
        var id: String { item.id }
    }
    private(set) var entries: [Entry] = []
    private(set) var indices: [String: Int] = [:]

    init(_ input: FolderOutlineInput? = nil) {
        guard let input else { return }
        entries.reserveCapacity(input.roots.count)
        indices.reserveCapacity(input.roots.count)
        func append(_ items: [DiskItem], depth: Int, parentID: String?) {
            for item in items {
                let id = item.id
                guard indices[id] == nil else { continue }
                indices[id] = entries.count
                entries.append(Entry(item: item, depth: depth, parentID: parentID))
                if input.expanded.contains(id), let children = input.children[id] {
                    append(children, depth: depth + 1, parentID: id)
                }
            }
        }
        append(input.roots, depth: 0, parentID: nil)
    }

    subscript(id: String?) -> Entry? {
        guard let id, let index = indices[id] else { return nil }
        return entries[index]
    }
}

/// Files tree mode. Sizes come from the measured scan; selecting a folder selects its
/// whole current subtree at review time, and the review sheet rechecks identities.
struct FolderTreeView: View {
    @Environment(AppModel.self) var model
    @Environment(AISettings.self) var ai
    var store: FolderTreeStore
    @Binding var selection: [String: DiskItem]
    let items: [DiskItem]
    var selectionEnabled = true
    var blocked: (DiskItem) -> Bool = { _ in false }
    var scope: DeveloperScope? = nil
    var onApplyExclusions: (([DiskItem]) -> Void)? = nil
    var onSaveAsScope: (([DiskItem]) -> Void)? = nil
    var hint = "Expand a folder to inspect it. Selecting a folder includes its contents at review."
    var onInspect: ((DiskItem) -> Void)? = nil
    @State private var explainTarget: AIExplainTarget?
    @State private var showPlan = false
    @State private var planUndoSelection: [String: DiskItem]?
    @State private var focusedRowID: String?
    @FocusState private var treeFocused: Bool
    @State private var outline = FolderOutline()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(hint + " Use up/down arrows, Space to select, left/right to collapse or expand.").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
                Spacer()
                if let planUndoSelection {
                    Button { selection = planUndoSelection; self.planUndoSelection = nil } label: { Label("Undo AI plan", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        .help("Restore the selection from before the last AI plan")
                }
                if ai.enabled && selectionEnabled && !items.isEmpty {
                    Button { showPlan = true } label: { Label("Draft with AI", systemImage: "sparkles") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                        .help("Turn a sentence into a top-level selection; nothing is moved")
                }
                if !store.expanded.isEmpty { Button("Collapse all") { store.collapseAll() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Theme.line)
            if outline.entries.isEmpty {
                Text("No items measured in this folder.").font(.system(size: 12)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(outline.entries) { entry in
                                let row = rowData(entry)
                                VStack(spacing: 0) {
                                    TreeRowView(
                                        row: row,
                                        store: store,
                                        selection: $selection,
                                        selectionEnabled: selectionEnabled,
                                        aiEnabled: ai.enabled,
                                        focused: focusedRowID == row.id,
                                        onFocus: {
                                            if focusedRowID == row.id { onInspect?(row.item) }
                                            focusedRowID = row.id
                                            treeFocused = true
                                        },
                                        onExplain: { requestExplain(row.item, scope: scope) }
                                    )
                                    Divider().overlay(Theme.line).padding(.leading, 24 + CGFloat(row.depth) * 14)
                                }
                            }
                        }
                    }
                    .onChange(of: focusedRowID) { _, id in
                        if let id { scroll.scrollTo(id) }
                    }
                }
                .focusable()
                .focused($treeFocused)
                .onKeyPress(.downArrow) { moveFocus(1); return .handled }
                .onKeyPress(.upArrow) { moveFocus(-1); return .handled }
                .onKeyPress(.space) { toggleFocusedSelection(); return .handled }
                .onKeyPress(.rightArrow) { expandFocused(); return .handled }
                .onKeyPress(.leftArrow) { collapseFocused(); return .handled }
                .onKeyPress(.return) { activateFocused(); return .handled }
                .accessibilityLabel("File tree")
                .accessibilityHint("Use up and down arrows to move, Space to select, left and right arrows to collapse or expand.")
            }
        }
        .frame(maxHeight: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
        .onDisappear { store.cancelPendingWork() }
        .sheet(item: $explainTarget) { AIExplainSheet(target: $0) }
        .onChange(of: FolderOutlineInput(roots: items, children: store.children, expanded: store.expanded), initial: true) { previous, next in
            outline = FolderOutline(next)
            if previous.roots != next.roots { planUndoSelection = nil }
            if let focusedRowID, outline[focusedRowID] == nil { self.focusedRowID = outline.entries.first?.id }
        }
        .onChange(of: focusedRowID.flatMap { outline[$0]?.item }) { _, item in
            if let item { onInspect?(item) }
        }
        .onChange(of: treeFocused) { _, focused in
            if focused, focusedRowID == nil { focusedRowID = outline.entries.first?.id }
        }
        .sheet(isPresented: $showPlan) {
            AIPlanSheet(
                items: items,
                blocked: blocked,
                scope: scope,
                evidence: { store.evidence(for: $0, sourceCheck: scope != nil) },
                currentSelection: selection,
                onCreateScope: scope == nil ? onSaveAsScope : nil,
                onApply: applyPlan
            )
        }
    }

    private func moveFocus(_ delta: Int) {
        let entries = outline.entries
        guard !entries.isEmpty else { return }
        let current = focusedRowID.flatMap { outline.indices[$0] } ?? (delta > 0 ? -1 : entries.count)
        let next = min(max(current + delta, 0), entries.count - 1)
        focusedRowID = entries[next].id
        treeFocused = true
    }

    private func toggleFocusedSelection() {
        guard selectionEnabled, !model.actionBusy, !model.scanning,
              let entry = outline[focusedRowID] else { return }
        let row = rowData(entry)
        guard !row.blocked, !row.checking, !row.item.incomplete else { return }
        let isOn = selection[row.item.id] == nil
        selection = TreeSelection.updated(selection, toggling: row.item, on: isOn)
    }

    private func expandFocused() {
        guard let entry = outline[focusedRowID], store.isFolder(entry.item) else { return }
        if store.expanded.contains(entry.id) { moveFocus(1) }
        else { store.toggle(entry.item) }
    }

    private func collapseFocused() {
        guard let entry = outline[focusedRowID] else { return }
        if store.expanded.contains(entry.id) { store.toggle(entry.item) }
        else if let parent = entry.parentID { focusedRowID = parent }
    }

    private func activateFocused() {
        guard let entry = outline[focusedRowID], store.isFolder(entry.item) else { return }
        store.toggle(entry.item)
    }

    private func applyPlan(_ selected: [DiskItem], _ excluded: [DiskItem]) {
        planUndoSelection = selection
        var next: [String: DiskItem] = [:]
        for item in selected where !blocked(item) && !item.incomplete {
            next = TreeSelection.updated(next, toggling: item, on: true)
        }
        selection = next
        if !excluded.isEmpty, let onApplyExclusions { onApplyExclusions(excluded) }
    }

    /// Reclassify before opening the sheet so the model never receives a "Checking…"
    /// placeholder as evidence. The sheet is only shown once real context exists.
    private func requestExplain(_ item: DiskItem, scope: DeveloperScope?) {
        Task {
            let evidence = await DiskWork.run("Inspecting \(item.name)", priority: .foreground) {
                CleanupEvidenceService.classify(item.url, sourceCheck: scope != nil)
            }
            await MainActor.run { explainTarget = AIExplainTarget(item: item, evidence: evidence, scope: scope) }
        }
    }

    private func rowData(_ entry: FolderOutline.Entry) -> TreeRowData {
        let item = entry.item
        let expanded = store.expanded.contains(entry.id)
        let loading = store.loading.contains(entry.id)
        let sourceCheck = entry.depth == 0
        let evidence = store.evidence(for: item, sourceCheck: sourceCheck)
        return TreeRowData(
            item: item,
            depth: entry.depth,
            evidence: evidence,
            expanded: expanded,
            loading: loading,
            partial: store.partial.contains(entry.id),
            empty: expanded && !loading && store.children[entry.id]?.isEmpty == true,
            blocked: blocked(item) || evidence.kind.isBlocked,
            checking: !store.evidenceReady(for: item, sourceCheck: sourceCheck)
        )
    }

}

private struct TreeRowView: View {
    @Environment(AppModel.self) var model
    let row: TreeRowData
    var store: FolderTreeStore
    @Binding var selection: [String: DiskItem]
    let selectionEnabled: Bool
    let aiEnabled: Bool
    let focused: Bool
    let onFocus: () -> Void
    let onExplain: () -> Void
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
            .disabled(!selectionEnabled || row.blocked || row.checking || row.item.incomplete || model.actionBusy || model.scanning)

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
            if aiEnabled && (hovered || row.evidence.kind == .unknown || row.evidence.kind == .sourceLike) {
                Button { onExplain() } label: {
                    Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Theme.orange)
                }.buttonStyle(.plain).help("Explain with AI — metadata only")
            }
            if row.loading { ProgressView().controlSize(.mini) }
            if row.checking { Text("Checking…").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            if row.blocked { Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(Theme.warning).help("This folder cannot be selected: it contains an excluded path or looks like a project/source root. Expand it to pick safe items.") }
            else if row.partial { Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(Theme.warning).help("Only part of this folder could be inspected. Review still rechecks every item.") }
            if row.empty { Text("Empty").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            Spacer(minLength: 12)
            if row.item.measurementPending == true {
                Button("Measure") { store.measure(row.item) }.buttonStyle(.plain).font(.system(size: 11)).disabled(row.loading)
            }
            Text(row.item.measurementPending == true ? "Not measured" : bytes(row.item.size) + (row.item.incomplete || row.partial ? "+" : ""))
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .padding(.leading, 12 + CGFloat(row.depth) * 14)
        .padding(.trailing, 14)
        .padding(.vertical, 5)
        .background(focused ? Theme.orange.opacity(0.10) : hovered ? Theme.rail.opacity(0.45) : .clear)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.orange, lineWidth: focused ? 1.5 : 0).padding(.horizontal, 2))
        .contentShape(Rectangle())
        .onAppear { store.requestEvidence(row.item, sourceCheck: row.depth == 0) }
        .onHover { hovered = $0 }
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
        .onTapGesture(count: 2) { if folder { store.toggle(row.item) } }
        .contextMenu { if aiEnabled { Button("Explain with AI…") { onExplain() } } }
        .accessibilityElement(children: .contain)
    }
}
