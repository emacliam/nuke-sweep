import SwiftUI
import Charts

struct MenuCPUChart: View {
    let interval: TimeInterval
    let samples: [MonitorSample]
    @State private var date: Date?
    var points: [ResourceChartPoint] { ResourceChartPoint.make(samples, memory: false, maximumGap: max(15, interval * 2.5)) }
    /// Only while the pointer is actually over the plot. `nearest` resolves to a
    /// point regardless, which made the header look like a live readout rather
    /// than an inspection of the hovered sample.
    var chosen: ResourceChartPoint? { date == nil ? nil : ChartInspection.nearest(points, date: date, dateOf: { $0.date }) }
    var body: some View {
        // A single plottable point is a dot in 70pt of empty axes, which reads as a
        // broken chart. History length is not the test: samples without a CPU
        // reading are dropped when the points are built.
        if points.count < 2 {
            Text("Collecting CPU history…").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        } else {
            chart
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent CPU")
                Spacer()
                if let chosen {
                    Text(verbatim: String(format: "%.1f%%", chosen.value)).monospacedDigit()
                    Text(verbatim: chosen.date.formatted(date: .omitted, time: .standard))
                } else {
                    Text("Hover to inspect").foregroundStyle(Theme.secondary)
                }
            }.font(.system(size: 10))
            Chart(points) { point in
                PointMark(x: .value("Time", point.date), y: .value("CPU %", point.value)).symbolSize(6).foregroundStyle(Theme.orange)
                LineMark(x: .value("Time", point.date), y: .value("CPU %", point.value), series: .value("Segment", point.segment)).foregroundStyle(Theme.orange)
            }.chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 100]) {
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                    AxisValueLabel().font(.system(size: 8)).foregroundStyle(Theme.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartXSelection(value: $date).chartOverlay { proxy in DateChartOverlay(proxy: proxy, selection: $date) }.frame(height: 70)
            .accessibilityLabel("Recent CPU history")
            if let first = points.first, let last = points.last, first.date != last.date {
                HStack {
                    Text(first.date.formatted(date: .omitted, time: .standard))
                    Spacer()
                    Text(last.date.formatted(date: .omitted, time: .standard))
                }.font(.system(size: 9)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
