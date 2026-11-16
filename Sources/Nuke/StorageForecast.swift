import Foundation

enum StorageForecast {
    struct Reading: Codable {
        let date: Date
        let free: Int64
        let capacity: Int64
    }

    static let day: TimeInterval = 86_400
    private static let key = "nuke.dailyStorageReadings"

    static func load() -> [Reading] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([Reading].self, from: $0) } ?? []
    }

    static func save(_ readings: [Reading]) {
        if let data = try? JSONEncoder().encode(readings) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func daysRemaining(in readings: [Reading], current: Reading) -> Int? {
        guard current.capacity > 0, current.free > 0, current.free <= current.capacity else { return nil }
        let recent = readings.filter {
            $0.capacity == current.capacity && $0.free >= 0 && $0.free <= $0.capacity
                && $0.date <= current.date && current.date.timeIntervalSince($0.date) <= 30 * day
        }.sorted { $0.date < $1.date }
        guard recent.count >= 5, let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 7 * day,
              current.date.timeIntervalSince(last.date) <= 2 * day else { return nil }

        // Median of slopes across pairs at least two days apart. An isolated
        // jump in usage has less influence than a sustained decline.
        var slopes: [Double] = []
        for (index, older) in recent.enumerated() {
            for newer in recent.dropFirst(index + 1) {
                let span = newer.date.timeIntervalSince(older.date) / day
                if span >= 2 { slopes.append(Double(older.free - newer.free) / span) }
            }
        }
        slopes.sort()
        guard !slopes.isEmpty else { return nil }
        let rate = slopes[slopes.count / 2]
        let decliningPairs = slopes.count(where: { $0 > 0 })
        guard rate >= 100_000_000, decliningPairs * 3 >= slopes.count * 2 else { return nil }
        let remaining = Double(current.free) / rate
        guard remaining <= 365 else { return nil }
        return max(1, Int(remaining.rounded(.up)))
    }
}
