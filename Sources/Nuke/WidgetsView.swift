import SwiftUI
import AppKit
import WidgetKit
import NukeMetrics
import NukeWidgetUI

struct WidgetsView: View {
    @EnvironmentObject var monitor: LiveMonitor
    var metrics: WidgetMetrics {
        guard let s = monitor.sample else { return .placeholder }
        return WidgetMetrics(date: s.date, totalDisk: s.disk.totalDisk > 0 ? s.disk.totalDisk : nil, freeDisk: s.disk.totalDisk > 0 ? s.disk.freeDisk : nil, cpu: s.cpu, memory: s.memory, physicalMemory: s.disk.physicalMemory)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Available storage at a glance. The widget shows when it last refreshed.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            StorageWidgetFace(metrics: metrics, compact: true).padding(16).frame(width: 174, height: 174).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
            VStack(alignment: .leading, spacing: 12) {
                Text("Add to your desktop").font(.system(size: 15, weight: .semibold))
                Text("Control-click the desktop, choose Edit Widgets, and search for Nuke Sweep. Choose Storage, then pick a size. Launch this Nuke Sweep build at least once after installation so macOS can discover its extension.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                HStack(spacing: 14) {
                    Button("Request widget refresh") { WidgetCenter.shared.reloadAllTimelines() }.buttonStyle(QuietButton())
                    Button("Reveal Nuke Sweep app") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }.buttonStyle(QuietButton())
                }
            }
            Notice(text: "The Storage widget is a snapshot. Use the menu bar for live CPU and memory readings. The extension asks for a refresh after 15 minutes; macOS controls the actual schedule. Widgets read system counters directly, share no personal files, and open Nuke Sweep when clicked. A local ad-hoc build may not be accepted by the widget gallery; see the widget setup guide if Nuke Sweep is missing.", symbol: "info.circle")
        }
    }
}
