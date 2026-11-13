import SwiftUI
import NukeMetrics
import AppKit
import NukeWidgetUI

@MainActor final class StatusBarController: NSObject, NSPopoverDelegate {
    private weak var model: AppModel?
    private let monitor: LiveMonitor
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var pendingUpdate: DispatchWorkItem?
    private var observing = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    init(model: AppModel) {
        self.model = model; monitor = model.features.monitor
        super.init()
        popover.behavior = .transient; popover.delegate = self
        observeDisplayedInputs()
        update()
    }
    /// Observation tracking is single-shot, so each change re-arms the next one.
    /// Only inputs displayed in the item are read here; history and alert
    /// bookkeeping must not redraw the status item.
    private func observeDisplayedInputs() {
        observing = true
        withObservationTracking {
            _ = monitor.sample
            _ = monitor.monitorPaused
            _ = monitor.sleeping
            _ = monitor.monitorEnabled
            _ = monitor.showStatusName
            _ = monitor.statusBarMetric
        } onChange: { [weak self] in
            // onChange runs before the new value is applied, so hop to the main
            // queue to read the settled state, then re-arm for the next change.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.observing else { return }
                self.scheduleUpdate()
                self.observeDisplayedInputs()
            }
        }
    }
    /// A burst of samples or setting changes should redraw the item once.
    private func scheduleUpdate() {
        pendingUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.update() }
        pendingUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
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
        // The tooltip and the spoken label carry the storage state, so a user who
        // cannot see the popover's colour still learns the disk is under pressure.
        let pressure = monitor.sample.map {
            StoragePressure.evaluate(free: $0.disk.freeDisk, total: $0.disk.totalDisk, thresholdGB: monitor.lowSpaceGB)
        } ?? .unavailable
        let state = pressure == .unavailable || monitor.monitorPaused || monitor.sleeping ? "" : " " + pressure.spoken + "."
        item?.button?.toolTip = "Nuke Sweep — " + mode.title + "." + state + " Click for storage, CPU, memory, and cleanup scopes."
        item?.button?.setAccessibilityLabel("Nuke Sweep. " + (reading ?? "Open monitor") + state)
    }
    @objc func toggle() { if popover.isShown { popover.close() } else { show() } }
    func show() {
        guard !popover.isShown, let button = item?.button, let model else { return }
        popover.contentViewController = NSHostingController(rootView: MonitorPopover().environment(model).environment(monitor))
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
    /// Isolated so the cleanup below can touch this actor's own stored
    /// properties; a nonisolated deinit reaching into them is a data race.
    isolated deinit {
        pendingUpdate?.cancel()
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
