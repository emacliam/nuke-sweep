import AppIntents
import Foundation

struct CheckThisMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Check This Mac"
    static let description = IntentDescription("Start a storage check in Nuke Sweep.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let model = NukeShortcuts.model else {
            return .result(dialog: "Open Nuke Sweep and finish setup before running a check.")
        }
        model.showMainWindow(.findSpace)
        if model.fullCheck.running {
            return .result(dialog: "Nuke Sweep is already checking this Mac.")
        }
        guard model.startFullCheck() else {
            return .result(dialog: "Nuke Sweep is busy. Try again when the current task finishes.")
        }
        return .result(dialog: "Nuke Sweep started checking this Mac. Results will appear in Cleanup.")
    }
}

struct ClearableSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Can I Clear?"
    static let description = IntentDescription("Get the estimated size of rebuildable items from your latest completed Nuke Sweep check.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let record = FullCheckHistory.last else {
            return .result(dialog: "Run Check This Mac in Nuke Sweep to get a storage estimate.")
        }
        let date = record.date.formatted(date: .abbreviated, time: .shortened)
        let measured = bytes(record.regenerableBytes)
        return .result(dialog: "On \(date), Nuke Sweep measured \(measured) in rebuildable items. Run a new check for a current estimate.")
    }
}

struct NukeShortcuts: AppShortcutsProvider {
    @MainActor static weak var model: AppModel?

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CheckThisMacIntent(), phrases: ["Check this Mac with \(.applicationName)"],
                    shortTitle: "Check This Mac", systemImageName: "internaldrive")
        AppShortcut(intent: ClearableSpaceIntent(), phrases: ["How much space can I clear with \(.applicationName)"],
                    shortTitle: "How Much Can I Clear?", systemImageName: "chart.bar")
    }
}
