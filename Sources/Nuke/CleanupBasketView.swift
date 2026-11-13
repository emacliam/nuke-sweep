import SwiftUI

struct CleanupBasketView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup basket").font(.system(size: 21, weight: .semibold))
            Text("Collect items while browsing different folders. These are proposals; review checks current contents and access before anything can move to Trash.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            if model.cleanupBasket.items.isEmpty {
                EmptyPanel(symbol: "tray", title: "Your basket is empty", detail: "Select files or generated folders, then choose Add to basket. You can return here from any page.")
            } else {
                Table(model.cleanupBasket.items, selection: $selection) {
                    TableColumn("Item") { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }.width(min: 240, ideal: 430)
                    TableColumn("Logical size") { Text(bytes($0.size) + ($0.incomplete ? "+" : "")) }.width(110)
                }.frame(minHeight: 200)
                HStack {
                    Button("Remove selected") { for id in selection { model.cleanupBasket.remove(id) }; selection = [] }.disabled(selection.isEmpty)
                    Button("Clear basket") { model.cleanupBasket.clear(); selection = [] }
                    Spacer()
                    Text("\(model.cleanupBasket.items.count) items").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                Button("Continue browsing") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Prepare review…") { model.basketReviewRequested = true; model.showCleanupBasket = false }
                    .buttonStyle(PrimaryButton()).disabled(model.cleanupBasket.items.isEmpty || model.actionBusy)
            }
        }.padding(24).frame(width: 700, height: 470)
    }
}
