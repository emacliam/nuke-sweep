import Foundation

struct WatchSchedule {
    private(set) var scanning = false
    private(set) var pending = false
    mutating func changed() { pending = true }
    mutating func begin() -> Bool {
        guard !scanning else { return false }; scanning = true; pending = false; return true
    }
    mutating func finish() -> Bool { scanning = false; return pending }
    mutating func clear() { scanning = false; pending = false }
}
