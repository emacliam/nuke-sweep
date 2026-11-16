import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CleanupImageSummary {
    let movedBytes: Int64
    let movedCount: Int
    let eligibleCount: Int
    let restoredCount: Int
    let otherSuccesses: Int
    let failedCount: Int

    init(items: [ReceiptItem]) {
        let moved = items.filter { $0.success && $0.trashPath != nil }
        movedBytes = moved.reduce(0) { total, item in
            total + min(max(0, item.size), Int64.max - total)
        }
        movedCount = moved.count
        eligibleCount = moved.filter { $0.restoredAt == nil && $0.restoreEvidence != nil }.count
        restoredCount = moved.filter { $0.restoredAt != nil }.count
        otherSuccesses = items.filter(\.success).count - moved.count
        failedCount = items.filter { !$0.success }.count
    }
}

struct CleanupResultImage: View {
    let summary: CleanupImageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Nuke Sweep", systemImage: "sparkle.magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.44))
            if summary.movedCount > 0 {
                Text("\(bytes(summary.movedBytes)) moved to Trash")
                    .font(.system(size: 36, weight: .semibold))
                Text("\(summary.movedCount) moved · \(summary.eligibleCount) marked eligible to restore · \(summary.restoredCount) restored")
                    .font(.system(size: 16))
                Text("Files still in Trash use disk space. Restore depends on the files still being available.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.78))
            } else {
                Text("Cleanup result").font(.system(size: 36, weight: .semibold))
            }
            if summary.otherSuccesses > 0 { Text("\(summary.otherSuccesses) other cleanup actions succeeded") }
            if summary.failedCount > 0 { Text("\(summary.failedCount) failed") }
        }
        .foregroundStyle(.white)
        .padding(36)
        .frame(width: 680, alignment: .leading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

struct CleanupImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let summary: CleanupImageSummary
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CleanupResultImage(summary: summary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if let error { Notice.measured(error, symbol: "exclamationmark.triangle") }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy image") { copyImage() }.buttonStyle(QuietButton())
                Button("Save PNG…") { saveImage() }.buttonStyle(PrimaryButton())
            }
        }.padding(22)
    }

    private func render() -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: CleanupResultImage(summary: summary))
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            error = "Could not create the cleanup image."
            return nil
        }
        return NSBitmapImageRep(cgImage: image)
    }

    private func copyImage() {
        guard let png = render()?.representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setData(png, forType: .png) { dismiss() }
        else { error = "Could not copy the cleanup image." }
    }

    private func saveImage() {
        guard let png = render()?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Nuke Sweep Cleanup.png"
        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try png.write(to: url, options: .atomic); self.dismiss() }
            catch { self.error = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: save) }
        else { panel.begin(completionHandler: save) }
    }
}
