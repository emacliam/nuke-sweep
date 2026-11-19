import SwiftUI

struct SimilarMediaView: View {
    @Environment(AppModel.self) private var model
    @State private var report: SimilarMedia.Report?
    @State private var scan: Task<Void, Never>?
    @State private var token: ScanCancellation?
    @State private var selected: String?
    @State private var keeper: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Similar photos and videos").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Choose folder…") {
                    FolderAccess.shared.chooseFolder(prompt: "Compare media") { root in start(root) }
                }.buttonStyle(PrimaryButton()).disabled(scan != nil)
                if scan != nil {
                    Button("Stop") { token?.cancel(); scan?.cancel() }.buttonStyle(QuietButton())
                }
            }
            Text("Compare loose files. Matches can look alike while containing different content, so preview both before choosing what to keep.")
                .foregroundStyle(Theme.secondary)
            if scan != nil {
                ProgressView("Comparing photos and video frames…")
            } else if let report {
                Text("\(report.compared) compared · \(report.skipped) skipped" + (report.partial ? " · Partial results" : ""))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                if report.matches.isEmpty { Text("No similar pairs found in the files compared.") }
                else {
                    HSplitView {
                        List(report.matches, selection: $selected) { match in
                            Text(match.first.name + " / " + match.second.name).tag(match.id)
                        }.frame(minWidth: 180, idealWidth: 230)
                        if let match = report.matches.first(where: { $0.id == selected }) {
                            comparison(match).frame(minWidth: 410)
                        } else {
                            Text("Select a pair to compare.").frame(minWidth: 410, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(minHeight: 290)
                }
            }
            Spacer()
        }
        .onChange(of: selected) { keeper = nil }
        .onDisappear { token?.cancel(); scan?.cancel() }
    }

    private func comparison(_ match: SimilarMedia.Match) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                file(match.first, preview: match.firstPreview)
                file(match.second, preview: match.secondPreview)
            }
            Button("Review the other file…") {
                let kept = keeper == match.first.id ? match.first : match.second
                let other = keeper == match.first.id ? match.second : match.first
                guard let identity = kept.identity, FileIdentity.read(kept.url) == identity else {
                    model.message = "The file you chose to keep changed. Compare the folder again."
                    return
                }
                model.reviewTrash([other])
            }.buttonStyle(PrimaryButton()).disabled(keeper == nil || model.actionBusy)
        }.padding(12)
    }

    private func file(_ item: DiskItem, preview: Data?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview, let image = NSImage(data: preview) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 125)
                    .accessibilityLabel("Preview of \(item.name)")
            }
            Text(item.name).fontWeight(.medium).lineLimit(2)
            Text(item.url.path).font(.system(size: 10)).lineLimit(2).truncationMode(.middle).help(item.url.path)
            Text(bytes(item.size)).monospacedDigit()
            Button(keeper == item.id ? "Keeping this file" : "Keep this file") { keeper = item.id }
                .buttonStyle(QuietButton())
                .accessibilityLabel("Keep \(item.name)")
            Button("Show in Finder") { model.reveal(item.url) }.buttonStyle(HoverPlain())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start(_ root: URL) {
        let cancellation = ScanCancellation()
        token = cancellation
        selected = nil
        keeper = nil
        report = nil
        scan = Task {
            let worker = Task.detached(priority: .utility) { await SimilarMedia.scan(root, token: cancellation) }
            let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            report = result
            scan = nil
        }
    }
}
