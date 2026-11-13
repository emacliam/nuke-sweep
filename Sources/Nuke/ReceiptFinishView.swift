import SwiftUI

struct ReceiptFinishView: View {
    @Environment(AppModel.self) var model
    @Environment(FeatureModel.self) var features
    @Environment(\.dismiss) private var dismiss
    let receipt: CleanupReceipt
    @State private var restoreError: String?
    private var currentItems: [ReceiptItem] {
        features.receipts.first(where: { $0.id == receipt.id })?.items ?? receipt.items
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cleanup result").font(.system(size: 23, weight: .semibold))
            if let error = features.error { Notice.measured(error, symbol: "exclamationmark.triangle") }
            Text(receipt.title).font(.system(size: 14))
            let moved = currentItems.filter { $0.success && $0.trashPath != nil }
            let failed = currentItems.filter { !$0.success }.count
            HStack {
                if !moved.isEmpty {
                    Text("\(moved.count) moved to Trash · \(bytes(moved.reduce(0) { $0 + $1.size })) logical size")
                } else {
                    Text("\(currentItems.filter(\.success).count) succeeded")
                }
                if failed > 0 { Text("\(failed) failed").foregroundStyle(Theme.error) }
            }.font(.system(size: 13, weight: .medium))
            if let delta = receipt.observedFreeDelta {
                Text("Change in available space: \(delta >= 0 ? "+" : "−")\(bytes(abs(delta))). This is the observed change across the volume.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            if !moved.isEmpty {
                Text("Items still in Trash continue to use disk space. Restore eligible items below.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            if let restoreError { Notice.measured(restoreError, symbol: "exclamationmark.triangle") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(currentItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.originalPath).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                            Text(item.outcome).font(.system(size: 11)).foregroundStyle(item.success ? Theme.secondary : Theme.error)
                            if item.restoredAt != nil {
                                Text("Restored to original folder").font(.system(size: 11))
                            } else if let trash = item.trashPath {
                                HStack {
                                    Button("Show in Trash") { model.reveal(URL(fileURLWithPath: trash)) }
                                    if item.success && item.restoreEvidence != nil {
                                        Button("Restore to original folder") {
                                            restoreError = nil
                                            model.restoreReceiptItem(item) { restoreError = $0 }
                                        }.disabled(model.actionBusy)
                                    }
                                }.buttonStyle(QuietButton())
                            }
                        }; Divider()
                    }
                }
            }.frame(maxHeight: 250)
            Text(receipt.undo).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack { Button("View receipt history") { dismiss(); model.page = .history }.buttonStyle(QuietButton()); Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
}
