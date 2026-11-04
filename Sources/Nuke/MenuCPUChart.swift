import SwiftUI
import Charts

struct MenuCPUChart: View {
    let interval: TimeInterval
    let samples: [MonitorSample]
    @State private var date: Date?
    var points: [ResourceChartPoint] { ResourceChartPoint.make(samples, memory: false, maximumGap: max(15, interval * 2.5)) }
    var chosen: ResourceChartPoint? { ChartInspection.nearest(points, date: date, dateOf: { $0.date }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Recent CPU"); Spacer(); if let chosen { Text(String(format: "%.1f%%", chosen.value)).monospacedDigit(); Text(chosen.date.formatted(date: .omitted, time: .standard)) } }.font(.system(size: 10))
            Chart(points) { point in
                RuleMark(y: .value("Alert threshold", 85))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.warning.opacity(0.45))
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
            .accessibilityLabel("Recent CPU history, alert threshold at 85 percent")
            HStack {
                if let first = points.first { Text(first.date.formatted(date: .omitted, time: .standard)) }
                Spacer()
                if let last = points.last { Text(last.date.formatted(date: .omitted, time: .standard)) }
            }.font(.system(size: 9)).foregroundStyle(Theme.secondary)
        }
    }
}
