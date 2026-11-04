import Foundation

/// Opt-in diagnostic only. No timer or file IO in normal launches.
enum UIResponsiveness {
    private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "local.nuke.responsiveness", qos: .utility)
    private static let pending = DispatchSemaphore(value: 1)
    static func startIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--measure-ui"), args.indices.contains(index + 1) else { return }
        let destination = URL(fileURLWithPath: args[index + 1])
        var samples: [Double] = []
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 3, repeating: .milliseconds(100), leeway: .milliseconds(10))
        source.setEventHandler {
            guard pending.wait(timeout: .now()) == .success else { return }
            let start = DispatchTime.now().uptimeNanoseconds
            DispatchQueue.main.async {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                queue.async {
                    samples.append(elapsed)
                    if samples.count > 6000 { samples.removeFirst(1000) }
                    let sorted = samples.sorted()
                    let report: [String: Any] = ["samples": samples.count, "max_ms": sorted.last ?? 0, "p95_ms": sorted[Int(Double(sorted.count - 1) * 0.95)], "over_250ms": samples.filter { $0 > 250 }.count]
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: destination, options: .atomic) }
                    pending.signal()
                }
            }
        }
        timer = source; source.resume()
    }
}
