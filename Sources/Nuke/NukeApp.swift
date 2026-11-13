import SwiftUI
import AppKit

@main struct NukeApp: App {
    @State private var model: AppModel
    @AppStorage("nuke.appearance") private var appearance = "system"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        AppEnvironment.migrateProductionPreferences()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("Nuke Sweep", id: "main") {
            ContentView().environment(model).environment(model.features).environment(model.features.monitor).environment(model.ai).environment(model.scheduledScans).frame(minWidth: 980, minHeight: 650)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        }
        .windowStyle(.hiddenTitleBar).defaultSize(width: 1180, height: 790)
        .commands {
            if ProcessInfo.processInfo.arguments.contains("--capture") {
                CommandMenu("Capture") {
                    Button("Capture current view") { AppDelegate.captureCurrent() }.keyboardShortcut("s", modifiers: [.command, .option, .shift])
                    Button("Close main window for monitor check") { NSApp.windows.first(where: { $0.title == "Nuke Sweep" })?.performClose(nil) }.keyboardShortcut("w", modifiers: [.command, .option, .shift])
                    Button("Preview result sheet — no files changed") {
                        model.finishedReceipt = CleanupReceipt(date: Date(), title: "Interface preview — no cleanup executed", items: [.init(originalPath: "/tmp/interface-preview/Cache", trashPath: nil, size: 0, success: true, outcome: "Sample success state only; no file was moved."), .init(originalPath: "/tmp/interface-preview/Unavailable", trashPath: nil, size: 0, success: false, outcome: "Sample failure state only; no file was moved.")], freeBefore: nil, freeAfter: nil, undo: "This is an interface validation preview. Real receipts include measured outcomes and restoration paths.")
                    }.keyboardShortcut("p", modifiers: [.command, .option, .shift])
                    Button("Simulate monitor sleep") { model.sleep() }.keyboardShortcut("b", modifiers: [.command, .option, .shift])
                    Button("Simulate monitor wake") { model.wake() }.keyboardShortcut("u", modifiers: [.command, .option, .shift])
                }
            }
            CommandGroup(after: .appInfo) { Button("Check for Updates…") { model.page = .updates; model.showMainWindow() } }
            CommandGroup(replacing: .newItem) { Button("Scan Folder…") { model.chooseFolder() }.keyboardShortcut("o"); Button("Refresh") { model.refreshResources(); if model.page == .storage { model.scan() } }.keyboardShortcut("r") }
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Filter") { model.focusFilterRequest += 1 }.keyboardShortcut("f")
            }
            CommandMenu("Go") {
                Button("Cleanup") { model.page = .findSpace }.keyboardShortcut("1")
                Button("Files") { model.page = .storage }.keyboardShortcut("2")
                Button("Apps") { model.page = .apps }.keyboardShortcut("3")
                Button("History") { model.page = .history }.keyboardShortcut("4")
                Button("Settings") { model.page = .monitor }.keyboardShortcut("5")
            }
        }

    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    weak var model: AppModel?
    private var sleepObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?
    private var windowOpenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    override init() { super.init(); Self.shared = self }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { model?.showMainWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.actionBusy else { return .terminateNow }
        if model.reviewPreparing { model.cancelReview(); return .terminateNow }
        model.quitWhenIdle = true
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        Log.lifecycle.info("Terminating")
        model?.saveSession(); FilePersistence.flush(); CommandRunner.shutdown()
    }
    static func captureCurrent() {
        guard let view = NSApp.keyWindow?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: "/tmp/nuke-current.png")) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `NSWindow.title` is main-actor state. These observers are already
        // delivered on .main, but that is a runtime fact the compiler cannot
        // check, so the window is identified inside an explicit hop.
        // Registered with `queue: .main`, so these bodies genuinely run on the
        // main actor. `assumeIsolated` states that rather than sending a
        // non-Sendable NSWindow across isolation, and traps if it ever stops
        // being true.
        windowOpenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            // `Notification` is not Sendable and NotificationCenter is not
            // annotated for concurrency, so the compiler cannot see that
            // `queue: .main` already guarantees main-thread delivery. The unsafe
            // binding records that guarantee; `assumeIsolated` enforces it at
            // runtime and traps if it is ever violated.
            nonisolated(unsafe) let delivered = notification
            MainActor.assumeIsolated {
                guard let window = delivered.object as? NSWindow, window.title == "Nuke Sweep" else { return }
                self?.model?.mainWindowVisible = true
            }
        }
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            nonisolated(unsafe) let delivered = notification
            MainActor.assumeIsolated {
                guard let window = delivered.object as? NSWindow, window.title == "Nuke Sweep" else { return }
                if !NSApp.windows.contains(where: { $0.title == "Nuke Sweep" && $0.isVisible }) { self?.model?.mainWindowVisible = false }
            }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model?.sleep() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.model?.wake() } }
        Log.lifecycle.info("Launched: version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown", privacy: .public)")
        UIResponsiveness.startIfRequested()
        HangWatchdog.startIfEnabled()
        if ProcessInfo.processInfo.arguments.contains("--simulate-hang") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Thread.sleep(forTimeInterval: 3) }
        }
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--compact") {
            NSApp.windows.first?.setContentSize(NSSize(width: 980, height: 650))
        }
        if ProcessInfo.processInfo.arguments.contains("--capture") {
            // The menu-bar popover is a separate window, so it needs showing before
            // the capture and must be captured as the key window.
            if ProcessInfo.processInfo.arguments.contains("--capture-monitor") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.model?.statusController?.show()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { Self.capture(name: "monitor") }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                Self.capture(name: ProcessInfo.processInfo.arguments.contains("--compact") ? "compact" : "overview")
            }
        }
    }
    static func capture(name: String) {
        // The hidden-title-bar window can report an empty title, so prefer the largest
        // visible content window instead of matching the title exactly.
        let keyWindow = NSApp.keyWindow
        let window = ProcessInfo.processInfo.arguments.contains("--capture-key") || ProcessInfo.processInfo.arguments.contains("--capture-monitor")
            ? keyWindow
            : NSApp.windows
                .filter { $0.isVisible && $0.contentView != nil }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: "/tmp/nuke-" + name + ".png")) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !UserDefaults.standard.bool(forKey: "nuke.menuEnabled") }
}
