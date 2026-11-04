import Foundation

struct SimulatorDevice: Identifiable, Sendable {
    let id: String
    let name: String
    let runtime: String
    let state: String
    let available: Bool
    var logicalBytes: Int64? = nil
    var partialMeasurement = false
    var canDelete: Bool { UUID(uuidString: id) != nil && state == "Shutdown" }
}
struct SimulatorInventory: Sendable {
    var devices: [SimulatorDevice] = []
    var note = ""
}
struct SimulatorDeletion: Sendable { let success: Bool; let message: String }
enum EmulatorCleanup {
    typealias Runner = (String, [String]) -> CommandResult
    static func run(_ path: String, _ args: [String]) -> CommandResult { CommandRunner.run(path, args, timeout: 20) }
    static func simulators(runner: Runner = run) -> SimulatorInventory {
        // simctl's Xcode wrapper can install components. Never invoke it until first launch is complete.
        guard runner("/usr/bin/xcodebuild", ["-checkFirstLaunchStatus"]).status == 0 else {
            return .init(note: "Simulator inspection needs Xcode setup. Open Xcode and finish installing its components, then inspect again.")
        }
        let response = runner("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"])
        guard response.status == 0 else { return .init(note: "Simulator inventory unavailable. Open Xcode → Window → Devices and Simulators to check its setup.") }
        return decode(response.output)
    }
    static func measuredSimulators(token: ScanCancellation, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SimulatorInventory {
        var inventory = simulators()
        let deadline = Date().addingTimeInterval(15)
        for index in inventory.devices.indices.prefix(100) {
            guard !token.cancelled, Date() < deadline else { inventory.note += " Device size measurement stopped; some sizes are unknown."; break }
            let path = home.appendingPathComponent("Library/Developer/CoreSimulator/Devices").appendingPathComponent(inventory.devices[index].id)
            let scan = DiskScanner.scan(path, cancellation: token, deadline: deadline)
            if scan.skipped == 0 || scan.logical > 0 {
                inventory.devices[index].logicalBytes = scan.logical
                inventory.devices[index].partialMeasurement = scan.limited || scan.skipped > 0
            }
        }
        inventory.note += " Sizes cover default device folders only; logical bytes are not guaranteed reclaimed space."
        return inventory
    }
    static func decode(_ json: String) -> SimulatorInventory {
        struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        struct List: Decodable { let devices: [String: [Device]] }
        guard let list = try? JSONDecoder().decode(List.self, from: Data(json.utf8)) else { return .init(note: "Could not verify simulator inventory. No devices can be deleted.") }
        let devices = list.devices.flatMap { runtime, values in values.compactMap { device -> SimulatorDevice? in
            guard UUID(uuidString: device.udid) != nil else { return nil }
            return .init(id: device.udid, name: device.name, runtime: runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: ""), state: device.state, available: device.isAvailable == true)
        }}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return .init(devices: devices, note: "Deleting a shut-down simulator permanently removes its installed apps and test data. Runtimes are shared; remove those in Xcode Settings → Components.")
    }
    static func delete(_ device: SimulatorDevice, runner: Runner = run) -> SimulatorDeletion {
        guard device.canDelete else { return .init(success: false, message: "Refused: only verified, shut-down simulator devices can be deleted.") }
        let live = simulators(runner: runner)
        guard let current = live.devices.first(where: { $0.id == device.id }), current.canDelete else { return .init(success: false, message: "Refused: this device changed or is running. Inspect again. No device was deleted.") }
        let response = runner("/usr/bin/xcrun", ["simctl", "delete", current.id])
        return .init(success: response.status == 0, message: response.status == 0 ? "Deleted \(current.name) through Apple's simulator manager." : "Simulator deletion failed. Inspect again in Xcode. \(response.output.prefix(300))")
    }
    static func isAndroidSnapshot(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let base = home.appendingPathComponent(".android/avd").standardizedFileURL
        let path = url.standardizedFileURL
        guard path.lastPathComponent == "snapshots", path.deletingLastPathComponent().pathExtension == "avd", path.deletingLastPathComponent().deletingLastPathComponent().path == base.path else { return false }
        return path.resolvingSymlinksInPath().path == base.resolvingSymlinksInPath().appendingPathComponent(path.deletingLastPathComponent().lastPathComponent).appendingPathComponent("snapshots").path
    }
    static func androidIdle(_ response: CommandResult) -> Bool {
        guard response.status == 0, !response.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !response.output.split(separator: "\n").contains { line in
            let command = URL(fileURLWithPath: String(line).trimmingCharacters(in: .whitespaces)).lastPathComponent.lowercased()
            return command == "emulator" || command.hasPrefix("qemu-system-") || command == "emulator64-arm" || command == "emulator64-x86"
        }
    }
    static func requireAndroidIdle(_ url: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let avds = home.appendingPathComponent(".android/avd").path
        guard url.standardizedFileURL.path.hasPrefix(avds + "/") else { return }
        guard androidIdle(CommandRunner.run("/bin/ps", ["-axo", "comm="], timeout: 5)) else {
            throw DuplicateFailure(message: "Close all Android emulators before cleaning saved snapshots. Running state could not be verified as idle.")
        }
    }
    static func androidSnapshots(home: URL = FileManager.default.homeDirectoryForCurrentUser, token: ScanCancellation) -> InventoryReport {
        var report = InventoryReport()
        let root = home.appendingPathComponent(".android/avd")
        for device in InventoryService.children(root, notes: &report.notes).filter({ $0.pathExtension == "avd" }).prefix(100) {
            if token.cancelled { break }
            let snapshots = device.appendingPathComponent("snapshots")
            guard isAndroidSnapshot(snapshots, home: home), let item = InventoryService.measure(snapshots, token: token) else { continue }
            report.entries.append(.init(item: item, category: "Android emulator snapshots", owner: device.deletingPathExtension().lastPathComponent, explanation: "Saved Quick Boot states only. Removing them requires a cold boot next time; the emulator's user-data disk is kept. Close all Android emulators before review."))
        }
        report.notes.append("Android snapshots can be moved to Trash. Android virtual devices and system images stay managed by Android Studio's Device and SDK Managers.")
        return report
    }
}
