import WidgetKit
import SwiftUI
import NukeMetrics
import NukeWidgetUI

struct NukeEntry: TimelineEntry {
    let date: Date
    let metrics: WidgetMetrics
}
struct NukeProvider: TimelineProvider {
    func placeholder(in context: Context) -> NukeEntry { NukeEntry(date: Date(), metrics: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (NukeEntry) -> Void) { sample(completion) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NukeEntry>) -> Void) {
        sample { entry in completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))) }
    }
    private func sample(_ completion: @escaping (NukeEntry) -> Void) {
        let before = SystemMetrics.cpuTicks()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) {
            let cpu = SystemMetrics.utilization(before: before, after: SystemMetrics.cpuTicks())
            let metrics = SystemMetrics.snapshot(cpu: cpu)
            completion(NukeEntry(date: metrics.date, metrics: metrics))
        }
    }
}
struct StorageEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: NukeEntry
    var body: some View {
        StorageWidgetFace(metrics: entry.metrics, compact: family == .systemSmall)
            .containerBackground(for: .widget) { WidgetPalette.background(for: colorScheme) }
            .widgetURL(URL(string: "nuke://storage"))
    }
}
struct ResourcesEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: NukeEntry
    var body: some View {
        ResourcesWidgetFace(metrics: entry.metrics, compact: family == .systemSmall)
            .containerBackground(for: .widget) { WidgetPalette.background(for: colorScheme) }
            .widgetURL(URL(string: "nuke://monitor"))
    }
}
struct NukeStorageWidget: Widget {
    let kind = "NukeStorage"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NukeProvider()) { entry in StorageEntryView(entry: entry) }
            .configurationDisplayName("Nuke Sweep Storage")
            .description("Available storage with the time it was measured.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct NukeResourcesWidget: Widget {
    let kind = "NukeResources"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NukeProvider()) { entry in ResourcesEntryView(entry: entry) }
            .configurationDisplayName("Nuke Sweep Resources")
            .description("A snapshot of CPU, VM memory, and available storage. Refresh timing is controlled by macOS.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main struct NukeWidgets: WidgetBundle {
    var body: some Widget { NukeStorageWidget() }
}
