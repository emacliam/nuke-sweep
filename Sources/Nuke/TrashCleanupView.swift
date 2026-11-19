import SwiftUI
import AppKit

struct TrashCleanupView: View {
    @Environment(AppModel.self) var model
    @State private var review: TrashDeletionPlan?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("This user’s Trash", systemImage: "trash").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Open in Finder") { NSWorkspace.shared.open(TrashService.current.root) }.buttonStyle(QuietButton())
                Button("Scan Trash") { model.inspectTrash() }.buttonStyle(PrimaryButton()).disabled(model.trashLoading || model.actionBusy)
            }
            Text("Inspects ~/.Trash on your home volume. External-drive Trash is not included.").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            if model.trashLoading {
                BusyLine(text: "Reading Trash…")
            } else if let error = model.trashError {
                Text("Trash contents unavailable").font(.system(size: 15, weight: .semibold))
                Notice.measured(error, symbol: "exclamationmark.triangle")
                AccessRecovery()
            } else if let snapshot = model.trashSnapshot {
                if !snapshot.complete {
                    let blocked = snapshot.entries.count - snapshot.verifiable.count
                    Notice(text: blocked > 0
                           ? "\(blocked) items could not be checked completely and cannot be deleted from here. Everything else can. Use Finder for those."
                           : "Only part of Trash could be read. Items not listed are untouched.", symbol: "exclamationmark.triangle")
                }
                if snapshot.entries.isEmpty {
                    EmptyPanel(symbol: "trash", title: "Nothing to empty", detail: "This Trash folder is empty. Items you move to Trash will appear after the next scan.")
                } else {
                    HStack {
                        Text("\(snapshot.entries.count) items · \(bytes(snapshot.size)) logical size").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let updated = model.trashUpdated { Text("Scanned \(updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }
                    HStack {
                        let selectable = Set(snapshot.verifiable.map(\.id))
                        Button(!selectable.isEmpty && model.trashSelected == selectable ? "Deselect all" : "Select all") {
                            model.trashSelected = model.trashSelected == selectable ? [] : selectable
                        }.buttonStyle(.borderless).disabled(selectable.isEmpty)
                        Spacer(); Text("Largest first").foregroundStyle(Theme.secondary)
                    }.font(.system(size: 11))
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.entries) { entry in
                            HStack(spacing: 12) {
                                Toggle("Select \(entry.item.name)", isOn: Binding(get: { model.trashSelected.contains(entry.id) }, set: { if $0 { model.trashSelected.insert(entry.id) } else { model.trashSelected.remove(entry.id) } })).labelsHidden().toggleStyle(.checkbox).disabled(!entry.verifiable)
                                    .help(entry.verifiable ? "" : "Could not be checked completely, so it cannot be deleted from here. Use Finder.")
                                Image(systemName: entry.item.symlink ? "link" : entry.item.directory ? "folder" : "doc").foregroundStyle(Theme.secondary)
                                Text(entry.item.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(bytes(entry.item.size)).font(.system(size: 11)).monospacedDigit()
                                Button { model.reveal(entry.item.url) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(HoverPlain()).help("Reveal in Finder").accessibilityLabel("Reveal item in Finder")
                            }.padding(14)
                            Divider()
                        }
                    }.background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))
                    Notice(text: "Emptying Trash permanently deletes files. Logical size is not guaranteed recovered space: hard links, APFS sharing, and snapshots can affect the result. New top-level arrivals are excluded; changed items require a new scan.", symbol: "exclamationmark.triangle")
                    HStack {
                        Text("\(model.trashSelected.count) selected").font(.system(size: 11))
                        Spacer()
                        Button(model.trashSelected.count == snapshot.verifiable.count && snapshot.complete ? "Review emptying Trash…" : "Review selected…") {
                            review = TrashDeletionPlan(entries: snapshot.entries.filter { model.trashSelected.contains($0.id) }, rootIdentity: snapshot.rootIdentity)
                        }.buttonStyle(PrimaryButton()).disabled(model.trashSelected.isEmpty || model.actionBusy)
                    }
                }
            }
            Text("macOS may require Full Disk Access to inspect Trash. Nuke Sweep does not change your privacy settings.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
        .sheet(item: $review) { plan in PermanentTrashReview(plan: plan) }
    }
}
private struct TrashDeletionPlan: Identifiable {
    let id = UUID()
    let entries: [TrashEntry]
    let rootIdentity: FileIdentity
}
private struct PermanentTrashReview: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let plan: TrashDeletionPlan
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Permanently delete Trash items?", systemImage: "trash.slash").font(.system(size: 21, weight: .semibold))
            Text("\(plan.entries.count) reviewed items · \(bytes(plan.entries.reduce(0) { $0 + $1.item.size })) logical size").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(plan.entries) { entry in Text(entry.item.name).font(.system(size: 12)); Divider() }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 380)
            Notice(text: "This cannot be undone through Trash. Every selected folder and its contents will be permanently removed. Items changed since the scan are refused. Files can still change during deletion; stop apps using these items first.", symbol: "exclamationmark.triangle")
            Text("Type EMPTY to confirm permanent deletion.").font(.system(size: 12, weight: .medium))
            TextField("EMPTY", text: $confirmation).textFieldStyle(.roundedBorder).accessibilityLabel("Type EMPTY to confirm permanent deletion")
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Permanently delete \(plan.entries.count) items", role: .destructive) {
                    guard confirmation == "EMPTY" else { return }
                    dismiss(); model.permanentlyDeleteTrash(plan.entries, rootIdentity: plan.rootIdentity)
                }.buttonStyle(.borderedProminent).tint(.red).disabled(confirmation != "EMPTY" || model.actionBusy)
            }
        }.padding(30).frame(width: 560)
    }
}

extension AppModel {
    /// One step from anywhere: inspect Trash, then confirm deleting all of it.
    func emptyTrash() {
        guard !actionBusy, !trashLoading else { return }
        emptyTrashPending = true
        inspectTrash()
    }
}

/// The confirmation for Empty Trash. It appears only once the inspection is
/// complete, names what will go, and says plainly that it cannot be undone.
struct EmptyTrashConfirmation: ViewModifier {
    @Environment(AppModel.self) var model
    func body(content: Content) -> some View {
        let snapshot = model.trashSnapshot
        let ready = model.emptyTrashPending && !model.trashLoading
        content
            .confirmationDialog(
                snapshot.map { "Permanently delete \($0.verifiable.count) items (\(bytes($0.verifiable.reduce(0) { $0 + $1.item.size }))) in Trash?" } ?? "Trash could not be read",
                isPresented: Binding(get: { ready }, set: { if !$0 { model.emptyTrashPending = false } }),
                titleVisibility: .visible
            ) {
                if let snapshot, !snapshot.verifiable.isEmpty {
                    Button("Empty Trash", role: .destructive) {
                        model.emptyTrashPending = false
                        model.permanentlyDeleteTrash(snapshot.verifiable, rootIdentity: snapshot.rootIdentity)
                    }
                }
                Button("Cancel", role: .cancel) { model.emptyTrashPending = false }
            } message: {
                if let snapshot, snapshot.entries.isEmpty {
                    Text("Trash is already empty.")
                } else if let snapshot, snapshot.verifiable.isEmpty {
                    Text("Trash could only be read in part, so it is not emptied from here. Review it on the Trash page or in Finder.")
                } else if let snapshot {
                    let skipped = snapshot.entries.count - snapshot.verifiable.count
                    Text("This cannot be undone. Items cleaned up earlier can no longer be put back from History." + (skipped > 0 ? " \(skipped) items that could not be checked are left alone." : ""))
                } else {
                    Text(model.trashError ?? "Allow Full Disk Access, then try again.")
                }
            }
    }
}
