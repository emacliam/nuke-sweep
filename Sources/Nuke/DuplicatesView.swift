import SwiftUI

/// Native Table virtualizes group rows. Individual copies are paged separately:
/// neither a large result set nor one very large group builds thousands of controls.
struct DuplicatesView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @State private var keepers: [String: String] = [:]
    @State private var selected = Set<String>()
    @State private var search = ""
    @State private var inspecting: DuplicateGroup?
    private var groups: [DuplicateGroup] { features.duplicates?.groups ?? [] }
    private var visible: [DuplicateGroup] {
        guard !search.isEmpty else { return groups }
        return groups.filter { $0.files.contains { $0.url.path.localizedStandardContains(search) } }
    }
    private func keeper(_ group: DuplicateGroup) -> DiskItem? {
        group.files.first { $0.id == (keepers[group.id] ?? group.files.first?.id) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Duplicates").font(.system(size: 23, weight: .semibold))
            HStack {
                Text(features.duplicateRoot?.path ?? "Choose a folder to compare exact contents.").font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Find duplicates…") { features.findDuplicates() }.buttonStyle(PrimaryButton()).disabled(features.duplicateLoading)
            }
            if features.duplicateLoading { BusyLine(text: "Comparing files. Confirmed groups appear as the scan progresses; Stop preserves confirmed results.") }
            if let report = features.duplicates {
                Text("Read \(bytes(report.bytesRead)) of file data" + (report.stopReason.map { " · " + $0 } ?? "")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Text("\(report.groups.count) groups · \(report.checked) entries inspected · \(report.skipped) skipped" + (report.limited ? " · partial/stopped" : "")).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                HStack {
                    TextField("Filter by filename or folder", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                    Spacer()
                    Button("Inspect selected group…") { inspectSelected() }
                        .disabled(selected.count != 1)
                    Button("Select matching groups") { selected.formUnion(visible.map(\.id)) }.disabled(visible.isEmpty || features.duplicateLoading)
                    Button("Clear") { selected = [] }.disabled(selected.isEmpty)
                }.font(.system(size: 11))
                Table(visible, selection: $selected) {
                    TableColumn("Keep this file") { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(keeper(group)?.name ?? "Choose a keeper").font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(keeper(group)?.url.deletingLastPathComponent().path ?? "").font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }.width(min: 180, ideal: 320)
                    TableColumn("Copies") { Text(String($0.files.count)).monospacedDigit() }.width(55)
                    TableColumn("Extra logical size") { Text(bytes($0.extraBytes)).monospacedDigit() }.width(110)
                    TableColumn("Inspect") { group in
                        Button("Choose keeper…") { inspecting = group }.buttonStyle(.borderless)
                            .accessibilityLabel("Inspect \(group.files.count) copies of \(group.files.first?.name ?? "file")")
                    }.width(130)
                }.tableStyle(.inset(alternatesRowBackgrounds: false)).frame(minHeight: 180)
                    .onKeyPress(.return) {
                        guard selected.count == 1 else { return .ignored }
                        inspectSelected(); return .handled
                    }
                    .contextMenu(forSelectionType: String.self) { ids in
                        if ids.count == 1, let id = ids.first, let group = groups.first(where: { $0.id == id }) {
                            Button("Choose keeper…") { inspecting = group }
                        }
                    } primaryAction: { ids in
                        if ids.count == 1, let id = ids.first { inspecting = groups.first { $0.id == id } }
                    }
                HStack {
                    Text("\(selected.count) groups selected · keepers are retained").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Add other copies to basket") { review(addToBasket: true) }.buttonStyle(QuietButton()).disabled(selected.isEmpty || model.actionBusy || features.duplicateLoading)
                    Button("Review other copies…") { review() }.buttonStyle(PrimaryButton()).disabled(selected.isEmpty || model.actionBusy || features.duplicateLoading)
                }
                if visible.isEmpty { Text(features.duplicateLoading ? "No confirmed groups yet. Comparison is still running." : groups.isEmpty ? "No exact duplicates found within this scan’s coverage." : "No groups match this filter.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            } else if !features.duplicateLoading {
                SuggestedStart(
                    title: "Find identical files",
                    detail: "Pick the copies worth keeping, then review the others together. Nothing is selected automatically.",
                    symbol: "square.on.square",
                    choices: StartingPoints.forDuplicates.map { url, detail in
                        .init(url: url, detail: detail) {
                            FolderAccess.shared.remember(url)
                            features.findDuplicates(rootOverride: url)
                        }
                    }
                )
                Spacer()
            } else { Spacer() }
            Text("Identical contents can serve different purposes. Inspect the keepers before review. Logical size is not guaranteed reclaimed space; normal cleanup moves reviewed copies to Trash.").font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $inspecting) { group in
            DuplicateCopiesSheet(group: group, keeper: Binding(get: { keepers[group.id] ?? group.files.first?.id ?? "" }, set: { keepers[group.id] = $0 }))
        }
        .onChange(of: features.duplicateRoot) { _, _ in selected = []; keepers = [:]; search = "" }
        .onChange(of: features.duplicates?.groups.map(\.id)) { _, _ in selected = []; keepers = [:] }
    }
    private func inspectSelected() {
        guard selected.count == 1, let id = selected.first else { return }
        inspecting = groups.first { $0.id == id }
    }
    private func review(addToBasket: Bool = false) {
        guard let proposal = DuplicateSelection.prepare(groups: groups, selected: selected, keepers: keepers) else {
            model.message = "A keeper changed or is unavailable. Choose the keeper again before review."; return
        }
        guard !proposal.items.isEmpty else { return }
        if addToBasket { model.addToBasket(proposal.items, proofs: proposal.proofs) }
        else { model.reviewTrash(proposal.items, proofs: proposal.proofs) }
    }
}

private struct DuplicateCopiesSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    let group: DuplicateGroup
    @Binding var keeper: String
    @State private var search = ""
    @State private var page = 0
    @State private var selectedCopy: String?
    private let pageSize = 100
    private var filtered: [DiskItem] { search.isEmpty ? group.files : group.files.filter { $0.url.path.localizedStandardContains(search) } }
    private var pages: Int { max(1, (filtered.count + pageSize - 1) / pageSize) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the copy to keep").font(.system(size: 20, weight: .semibold))
            Text("\(group.files.count) identical files. The chosen keeper will never be included in this group’s cleanup proposal.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            TextField("Filter copies by path", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Text("Select a row, then choose which copy to keep.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Reveal selected") {
                    if let file = group.files.first(where: { $0.id == selectedCopy }) { model.reveal(file.url) }
                }.disabled(selectedCopy == nil)
                Button(selectedCopy == keeper ? "Keeping selected copy" : "Keep selected copy") {
                    if let selectedCopy { keeper = selectedCopy }
                }.disabled(selectedCopy == nil || selectedCopy == keeper)
            }
            List(Array(filtered.dropFirst(page * pageSize).prefix(pageSize)), selection: $selectedCopy) { file in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name).fontWeight(.medium)
                        Text(file.url.path).font(.system(size: 10)).foregroundStyle(Theme.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Reveal") { model.reveal(file.url) }
                    Button(keeper == file.id ? "Keeping" : "Keep this copy") { keeper = file.id }.disabled(keeper == file.id)
                }.padding(.vertical, 4).tag(file.id)
            }.listStyle(.inset)
            HStack {
                Button("Previous") { page -= 1 }.disabled(page == 0)
                Text("Page \(page + 1) of \(pages)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Button("Next") { page += 1 }.disabled(page + 1 >= pages)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 680, height: 500)
            .onAppear { selectedCopy = keeper }
            .onChange(of: search) { _, _ in page = 0; selectedCopy = nil }
            .onChange(of: page) { _, _ in selectedCopy = nil }
    }
}
