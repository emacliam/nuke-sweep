import SwiftUI
import AppKit
import Combine
import NukeWidgetUI

@MainActor final class StatusBarController: NSObject, NSPopoverDelegate {
    private weak var model: AppModel?
    private let monitor: LiveMonitor
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var updates: AnyCancellable?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    init(model: AppModel) {
        self.model = model; monitor = model.features.monitor
        super.init()
        popover.behavior = .transient; popover.delegate = self
        // Observe only inputs displayed in the item, not history/alert bookkeeping.
        updates = Publishers.MergeMany([
            monitor.$sample.map { _ in () }.eraseToAnyPublisher(),
            monitor.$monitorPaused.map { _ in () }.eraseToAnyPublisher(),
            monitor.$sleeping.map { _ in () }.eraseToAnyPublisher(),
            monitor.$monitorEnabled.map { _ in () }.eraseToAnyPublisher(),
            monitor.$showStatusName.map { _ in () }.eraseToAnyPublisher(),
            monitor.$statusBarMetric.map { _ in () }.eraseToAnyPublisher()
        ]).debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
          .sink { [weak self] _ in self?.update() }
        update()
    }
    private static func brandImage() -> NSImage {
        let size = NSSize(width: 18, height: 15)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            for accent in [false, true] {
                context.addPath(SweepSymbol(orangePart: accent).path(in: rect).cgPath)
                context.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nuke Sweep"
        return image
    }
    func update() {
        guard monitor.monitorEnabled else {
            popover.close(); if let item { NSStatusBar.system.removeStatusItem(item) }; item = nil; return
        }
        if item == nil {
            item = NSStatusBar.system.statusItem(withLength: 128)
            item?.button?.target = self; item?.button?.action = #selector(toggle)
            item?.button?.image = Self.brandImage()
            item?.button?.image?.isTemplate = true; item?.button?.imagePosition = .imageLeading
            item?.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        }
        let mode = StatusBarMetric(rawValue: monitor.statusBarMetric) ?? .storage
        let reading = monitor.monitorPaused ? "Paused" : monitor.sleeping ? "Sleeping" : mode.reading(monitor.sample)
        let title = reading.map { (monitor.showStatusName ? " Nuke Sweep " : " ") + $0 } ?? (monitor.showStatusName ? " Nuke Sweep" : "")
        // A stable slot avoids relaying out the system menu bar every time digits change.
        let width: CGFloat = mode == .icon && !monitor.monitorPaused && !monitor.sleeping ? (monitor.showStatusName ? 105 : 28) : (monitor.showStatusName ? 203 : 128)
        if item?.length != width { item?.length = width }
        if item?.button?.title != title { item?.button?.title = title }
        item?.button?.toolTip = "Nuke Sweep — " + mode.title + ". Click for storage, CPU, memory, and cleanup scopes."
        item?.button?.setAccessibilityLabel("Nuke Sweep. " + (reading ?? "Open monitor"))
    }
    @objc func toggle() { if popover.isShown { popover.close() } else { show() } }
    func show() {
        guard !popover.isShown, let button = item?.button, let model else { return }
        popover.contentViewController = NSHostingController(rootView: MonitorPopover().environmentObject(model).environmentObject(monitor).preferredColorScheme(.light))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        startDismissalMonitoring()
    }
    private func startDismissalMonitoring() {
        stopDismissalMonitoring()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global mouse monitoring sees other applications, not clicks inside Nuke.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.close()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.window === self.popover.contentViewController?.view.window { return event }
            // Let the status button's toggle handle its own click, without close-then-reopen.
            if let button = self.item?.button, event.window === button.window,
               button.bounds.contains(button.convert(event.locationInWindow, from: nil)) { return event }
            self.close()
            return event // The click still reaches its intended control/window.
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
    private func stopDismissalMonitoring() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor); self.localMouseMonitor = nil }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor); self.globalMouseMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
    }
    func popoverDidClose(_ notification: Notification) { stopDismissalMonitoring(); popover.contentViewController = nil }
    func close() { stopDismissalMonitoring(); popover.close() }
    deinit {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
