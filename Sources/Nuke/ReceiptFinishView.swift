import SwiftUI

struct ReceiptFinishView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var features: FeatureModel
    @Environment(\.dismiss) private var dismiss
    let receipt: CleanupReceipt
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cleanup result").font(.system(size: 23, weight: .semibold))
            if let error = features.error { Notice(text: error, symbol: "exclamationmark.triangle") }
            Text(receipt.title).font(.system(size: 14))
            HStack { Text("\(receipt.items.filter(\.success).count) succeeded"); Text("\(receipt.items.filter { !$0.success }.count) failed").foregroundStyle(Theme.error) }.font(.system(size: 13, weight: .medium))
            if let before = receipt.freeBefore, let after = receipt.freeAfter { Text("Observed available-space change: \(after >= before ? "+" : "−")\(bytes(abs(after - before))). Other activity and APFS sharing can affect this. Moving to Trash does not itself reclaim space.").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(receipt.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.originalPath).font(.system(size: 11, weight: .medium)).textSelection(.enabled)
                            Text(item.outcome).font(.system(size: 11)).foregroundStyle(item.success ? Theme.secondary : Theme.error)
                            if let trash = item.trashPath { Button("Show in Trash") { model.reveal(URL(fileURLWithPath: trash)) }.buttonStyle(.plain).font(.system(size: 11)) }
                        }; Divider()
                    }
                }
            }.frame(maxHeight: 250)
            Text(receipt.undo).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack { Button("View receipt history") { dismiss(); model.page = .history }.buttonStyle(QuietButton()); Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
}
