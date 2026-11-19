import SwiftUI
import QuickLook

struct PersonalFilesState: Equatable {
    var running = false
    var report: PersonalFiles.Report?
    var measured: Date?
    /// Item ids the person ticked. Never filled in for them.
    var selected = Set<String>()
    var expanded = Set<String>()
    var showingAll = Set<String>()
}

extension AppModel {
    /// Searches the home folder for the person's own surplus files. Measures
    /// and lists only; selecting and reviewing are separate, explicit steps.
    func scanPersonalFiles() {
        guard !personal.running else { return }
        personal.running = true
        let token = ScanCancellation(); personalToken = token
        var configured = PersonalFiles.Options()
        // The chosen code folder already has its own scan.
        configured.excluded = [fullCheck.projectsRoot ?? features.projectRoot].compactMap { $0 }
        let options = configured
        Task {
            let report = await DiskWork.run("Looking through your own files", cancellation: token) {
                PersonalFiles.scan(options, token: token)
            }
            guard personalToken === token else { return }
            personal.running = false
            personal.report = report
            personal.measured = Date()
            personal.selected.formIntersection(Set(report.findings.map(\.id)))
            if ProcessInfo.processInfo.arguments.contains("--capture-personal") {
                personal.expanded = Set(report.categories.prefix(2).map(\.rawValue))
            }
            Log.scan.notice("Personal files: findings=\(report.findings.count, privacy: .public) strayBuilds=\(report.strayBuilds.count, privacy: .public) visited=\(report.visited, privacy: .public) limited=\(report.limited, privacy: .public) unreadable=\(report.unreadable.count, privacy: .public)")
        }
    }

    func showPersonalFiles() {
        if let first = personal.report?.categories.first { personal.expanded = [first.rawValue] }
        scrollToPersonal = true
    }

    /// Files are moved, renamed and deleted outside the app. Anything listed
    /// that is no longer where it was is dropped, so the list never offers a
    /// file that is gone. Cheap: one lstat per listed item, off the main actor.
    func pruneMovedPersonalFiles() {
        guard let report = personal.report, !personal.running else { return }
        let listed = report.findings.map { ($0.item.url.path, $0.item.identity) } + report.strayBuilds.map { ($0.url.path, $0.identity) }
        Task {
            let gone = await Task.detached(priority: .utility) {
                listed.filter { path, identity in FileIdentity.read(URL(fileURLWithPath: path)) != identity || identity == nil }.map(\.0)
            }.value
            guard !gone.isEmpty else { return }
            personalFilesMoved(gone)
            Log.scan.info("Personal files: dropped \(gone.count, privacy: .public) that moved or were removed")
        }
    }

    var personalSelectedItems: [DiskItem] {
        guard let report = personal.report else { return [] }
        return report.findings.filter { personal.selected.contains($0.id) && !$0.item.incomplete }.map(\.item)
    }

    func reviewPersonalSelection() {
        let items = personalSelectedItems
        guard !items.isEmpty else { return }
        reviewTrash(items)
    }

    /// Drops what a finished cleanup moved, so the list does not keep offering
    /// files that are already in Trash.
    func personalFilesMoved(_ paths: [String]) {
        guard personal.report != nil, !paths.isEmpty else { return }
        personal.report?.remove(paths: paths)
        personal.selected.subtract(paths)
    }
}

/// The person's own surplus files, grouped by why they were listed.
///
/// Shown under the check's answer and deliberately kept out of its figures:
/// those describe what comes back by itself, and nothing here does.
struct PersonalFilesPanel: View {
    @Environment(AppModel.self) var model
    @State private var previewURL: URL?
    @State private var shownCount: [String: Int] = [:]
    private static let preview = 6

    var body: some View {
        Surface {
            if let report = model.personal.report {
                if report.findings.isEmpty { empty(report) } else { results(report) }
            } else {
                BusyLine(text: "Looking through installers, downloads, recordings and backups…")
            }
        }.quickLookPreview($previewURL)
    }

    private func empty(_ report: PersonalFiles.Report) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("None of your own files stand out").font(.system(size: 14, weight: .semibold))
            Text("No leftover installers, repeat downloads, large old recordings or device backups were found.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            notes(report)
        }
    }

    private func results(_ report: PersonalFiles.Report) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your own files worth a look").font(.system(size: 15, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(bytes(report.totalBytes)) in \(report.findings.count) files and folders. \(bytes(report.redundantBytes)) of it has a reason beyond its age: the app is installed, another copy exists, or it can be fetched again.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.personal.running {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Look again") { model.scanPersonalFiles() }.buttonStyle(QuietButton()).disabled(model.actionBusy)
                }
            }
            Text("Nothing here rebuilds itself, so nothing is ticked for you and none of it is ever cleaned automatically.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.ink)
            VStack(spacing: 0) {
                ForEach(report.categories, id: \.self) { category in
                    section(category, report.findings(in: category))
                    Divider()
                }
            }
            notes(report)
            footer(report)
        }
    }

    @ViewBuilder private func section(_ category: PersonalFiles.Category, _ findings: [PersonalFiles.Finding]) -> some View {
        let open = model.personal.expanded.contains(category.rawValue)
        let total = findings.reduce(Int64(0)) { $0 + $1.item.size }
        let chosen = findings.filter { model.personal.selected.contains($0.id) }.count
        VStack(alignment: .leading, spacing: 8) {
            Button {
                // One group open at a time keeps the page short.
                model.personal.expanded = open ? [] : [category.rawValue]
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.secondary).frame(width: 10)
                    Image(systemName: category.symbol).font(.system(size: 12)).foregroundStyle(Theme.orange).frame(width: 18)
                    Text(verbatim: category.title).font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(findings.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
                    if chosen > 0 {
                        Text("\(chosen) ticked").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                    }
                    Spacer()
                    Text(verbatim: category.recovery.title).font(.system(size: 10))
                        .foregroundStyle(category.recovery == .onlyCopy ? Theme.warning : Theme.green)
                    Text(verbatim: bytes(total)).font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 76, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverPlain())
            .accessibilityLabel(Text(verbatim: category.title))
            .accessibilityValue(Text("\(findings.count) items, \(chosen) selected, \(bytes(total)), \(category.recovery.title)"))
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(Text(open ? "Collapses this group" : "Shows the files in this group"))
            if open {
                // Rows grow in steps of 50 with the page, rather than in a
                // small scroll box of their own.
                let limit = min(300, shownCount[category.rawValue] ?? Self.preview)
                let shown = Array(findings.prefix(limit))
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: category.explanation).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    LazyVStack(alignment: .leading, spacing: 6) { ForEach(shown) { finding in row(finding) } }
                    HStack(spacing: 14) {
                        if findings.count > shown.count && limit < 300 {
                            Button("Show \(min(50, findings.count - shown.count)) more") { shownCount[category.rawValue] = limit + 50 }
                        }
                        if limit > Self.preview {
                            Button("Show fewer") { shownCount[category.rawValue] = nil }
                        }
                        let ids = Set(findings.filter { !$0.item.incomplete }.prefix(300).map(\.id))
                        if !ids.isEmpty, ids.isSubset(of: model.personal.selected) {
                            Button("Untick this group") { model.personal.selected.subtract(ids) }
                                .disabled(model.actionBusy)
                        } else if !ids.isEmpty {
                            let title: LocalizedStringKey = findings.count > 300 ? "Tick the largest 300" : "Tick this whole group"
                            Button(title) { model.personal.selected.formUnion(ids) }
                                .disabled(model.actionBusy)
                                .help("Ticks them for review. Nothing moves until you confirm in the review.")
                        }
                        Spacer()
                    }
                    .buttonStyle(HoverPlain()).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.orange)
                }
                .padding(.leading, 38).padding(.bottom, 4)
            }
        }
        .padding(.vertical, 9)
    }

    private func row(_ finding: PersonalFiles.Finding) -> some View {
        let size = bytes(finding.item.size) + (finding.item.incomplete ? "+" : "")
        let reason = finding.reason + (finding.item.incomplete ? " · " + String(localized: "could not be measured completely") : "")
        return HStack(alignment: .top, spacing: 9) {
            Toggle(isOn: Binding(
                get: { model.personal.selected.contains(finding.id) },
                set: { if $0 { model.personal.selected.insert(finding.id) } else { model.personal.selected.remove(finding.id) } }
            )) { Text(verbatim: finding.item.name) }
            .labelsHidden().toggleStyle(.checkbox).disabled(finding.item.incomplete || model.actionBusy)
            .accessibilityLabel(Text("Select \(finding.item.name) for review"))
            .accessibilityHint(Text(verbatim: "\(size). \(reason)"))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: finding.item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    if finding.redundant {
                        Image(systemName: "checkmark.circle").font(.system(size: 9)).foregroundStyle(Theme.green)
                    }
                    Text(verbatim: reason)
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: size).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary)
            if !finding.item.directory && !finding.item.symlink {
                Button {
                    previewURL = finding.item.url
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(HoverPlain())
                .onKeyPress(.space) { previewURL = finding.item.url; return .handled }
                .accessibilityLabel("Preview \(finding.item.name)")
                .help("Quick Look")
            }
            Button("Show") { model.reveal(finding.item.url) }
                .buttonStyle(HoverPlain()).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                .accessibilityLabel("Show \(finding.item.name) in Finder")
                .help(finding.item.url.path)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func notes(_ report: PersonalFiles.Report) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !report.strayBuilds.isEmpty {
                Text("\(bytes(report.strayBuilds.reduce(0) { $0 + $1.size })) of build and dependency folders were found in \(report.strayProjectRoots.count) projects outside your code folder. They are counted in the figures above.")
            }
            if !report.unreadable.isEmpty {
                Text("macOS did not allow reading \(report.unreadable.map { URL(fileURLWithPath: $0).lastPathComponent }.prefix(4).joined(separator: ", ")), so anything there is missing from this list. Allowing Full Disk Access includes it.")
            }
            if !report.syncFolders.isEmpty {
                Text("Left alone on purpose: \(report.syncFolders.prefix(4).joined(separator: ", ")). Removing a synced file removes it from every device.")
            }
            if report.cloudOnly > 0 {
                Text("\(report.cloudOnly) files exist only in the cloud and take no space here, so they are not listed.")
            }
            if report.limited {
                Text("The search stopped at its time or size limit, so this list may be incomplete.")
            }
            Text("Not looked at: photo libraries, mail, messages, and the inside of apps and project files.")
        }
        .font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func footer(_ report: PersonalFiles.Report) -> some View {
        let items = model.personalSelectedItems
        return HStack(spacing: 10) {
            if items.isEmpty {
                Text("Tick what you no longer need, then review it.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            } else {
                Text("\(items.count) ticked · \(bytes(items.reduce(0) { $0 + $1.size }))").font(.system(size: 11, weight: .medium)).monospacedDigit()
                Button("Untick all") { model.personal.selected = [] }.buttonStyle(HoverPlain()).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Review ticked files…") { model.reviewPersonalSelection() }
                .buttonStyle(PrimaryButton()).disabled(items.isEmpty || model.actionBusy)
                .help("Opens the review with these files listed. They move to Trash only after you confirm there, and the receipt can put them back.")
        }
    }
}
