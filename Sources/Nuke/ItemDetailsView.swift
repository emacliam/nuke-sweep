import SwiftUI

struct AssessmentSummary: View {
    let assessment: CandidateAssessment
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(assessment.state.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(assessment.canSelect ? Theme.ink : Theme.warning)
            Text(assessment.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            detail("Local evidence", assessment.evidence)
            detail("What cleanup means", assessment.consequences)
            detail("Still unknown", assessment.unknowns)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func detail(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10, weight: .semibold)).padding(.top, 4)
            ForEach(lines, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
        }
    }
}
struct ItemDetailsView: View {
    @Environment(AppModel.self) var model
    @Environment(AISettings.self) var ai
    let item: DiskItem
    @State private var evidence: CleanupEvidence?
    @State private var explainTarget: AIExplainTarget?
    private var assessment: CandidateAssessment {
        let reason = DeveloperScope.cleanupBlock(for: item.url.standardizedFileURL.path, in: model.features.developerScopes)
        return .make(item, evidence: evidence, scopeBlocked: reason != nil)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                AssessmentSummary(assessment: assessment)
                Button("Check running use…") { model.features.inspectUse(item.url) }
                    .buttonStyle(QuietButton()).disabled(model.features.useLoading)
                if ai.enabled, assessment.state == .needsInspection, let evidence {
                    Button("Ask AI about this item…") { explainTarget = .init(item: item, evidence: evidence, scope: nil) }
                        .buttonStyle(QuietButton())
                }
                Divider()
                Button("Reveal in Finder") { model.reveal(item.url) }.buttonStyle(QuietButton())
                if item.directory && !item.symlink {
                    Button("Browse this folder") { model.browseTree(item.url) }.buttonStyle(QuietButton()).disabled(model.scanning)
                    if evidence?.kind.supportsContentsReview == true {
                        Button("Review folder contents…") { model.reviewTrash([], folderContents: item) }
                            .buttonStyle(QuietButton()).disabled(!assessment.canSelect || model.actionBusy || model.scanning)
                            .help("Review a batch of immediate items while keeping this folder.")
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.system(size: 15, weight: .semibold)).textSelection(.enabled)
                Text(item.url.path).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                    .lineLimit(2).truncationMode(.middle).help(item.url.path).textSelection(.enabled)
                Text(item.measurementPending == true ? "Not measured" : bytes(item.size) + (item.incomplete ? "+ · partial" : " logical size")).font(.system(size: 11)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Divider() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button("Review this item…") { model.reviewTrash([item]) }.buttonStyle(PrimaryButton())
                Button("Add to basket") { model.addToBasket([item]) }.buttonStyle(QuietButton())
            }
            .disabled(!assessment.canSelect || model.actionBusy || model.scanning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.surface)
            .overlay(alignment: .top) { Divider() }
        }
        .background(Theme.surface)
            .task(id: item) {
                evidence = nil
                let token = ScanCancellation()
                await withTaskCancellationHandler {
                    let result = await DiskWork.run("Assessing selected item", cancellation: token) { CleanupEvidenceService.classify(item.url, sourceCheck: true) }
                    guard !Task.isCancelled else { return }; evidence = result
                } onCancel: { token.cancel() }
            }
            .sheet(item: $explainTarget) { AIExplainSheet(target: $0, previewBeforeSending: true) }
    }
}
