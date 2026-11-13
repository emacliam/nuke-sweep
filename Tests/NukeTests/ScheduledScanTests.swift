import XCTest
@testable import Nuke

final class ScheduledScanTests: XCTestCase {
    func testFrequenciesAdvanceTheCorrectInterval() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(ScanFrequency.hourly.next(after: base).timeIntervalSince(base), 3_600, accuracy: 0.001)
        XCTAssertEqual(ScanFrequency.daily.next(after: base).timeIntervalSince(base), 86_400, accuracy: 0.001)
        XCTAssertEqual(ScanFrequency.weekly.next(after: base).timeIntervalSince(base), 604_800, accuracy: 0.001)
    }

    func testScheduledScanRoundTrips() throws {
        let next = Date(timeIntervalSince1970: 2_000_000)
        let schedule = ScheduledScan(path: "/Users/example/Downloads", frequency: .daily, nextRun: next)
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(ScheduledScan.self, from: data)
        XCTAssertEqual(decoded, schedule)
        XCTAssertEqual(decoded.name, "Downloads")
        XCTAssertEqual(decoded.url.path, "/Users/example/Downloads")
    }

    func testDisabledSchedulesRemainValid() {
        var schedule = ScheduledScan(path: "/tmp/example", frequency: .weekly, nextRun: Date())
        schedule.enabled = false
        XCTAssertFalse(schedule.enabled)
        XCTAssertEqual(schedule.frequency.title, "Weekly")
    }
}

@MainActor
final class ScheduledScanStoreTests: XCTestCase {
    func testStorePersistsAddToggleFrequencyAndRemove() {
        let suite = "nuke.tests.schedules." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ScheduledScanStore(defaults: defaults)
        let id = store.add(URL(fileURLWithPath: "/tmp/nuke-schedule"), frequency: .daily)
        XCTAssertEqual(store.scans.count, 1)
        XCTAssertTrue(store.scans[0].enabled)

        store.toggle(id, enabled: false)
        XCTAssertFalse(store.scans[0].enabled)
        store.setFrequency(id, frequency: .weekly)
        XCTAssertEqual(store.scans[0].frequency, .weekly)

        let reloaded = ScheduledScanStore(defaults: defaults)
        XCTAssertEqual(reloaded.scans.count, 1)
        XCTAssertEqual(reloaded.scans[0].id, id)
        XCTAssertEqual(reloaded.scans[0].frequency, .weekly)
        XCTAssertFalse(reloaded.scans[0].enabled)

        store.remove(id)
        XCTAssertTrue(store.scans.isEmpty)
        XCTAssertTrue(ScheduledScanStore(defaults: defaults).scans.isEmpty)

        store.setQuietHoursEnabled(true)
        store.setQuietTime(\.startMinute, minute: 23 * 60)
        store.setQuietTime(\.endMinute, minute: 6 * 60)
        let quietReloaded = ScheduledScanStore(defaults: defaults)
        XCTAssertTrue(quietReloaded.quietHours.enabled)
        XCTAssertEqual(quietReloaded.quietHours.startMinute, 23 * 60)
        XCTAssertEqual(quietReloaded.quietHours.endMinute, 6 * 60)
    }

    func testAddingSameFolderUpdatesInsteadOfDuplicating() {
        let suite = "nuke.tests.schedules." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScheduledScanStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/nuke-schedule-same")
        _ = store.add(url, frequency: .hourly)
        _ = store.add(url, frequency: .weekly)
        XCTAssertEqual(store.scans.count, 1)
        XCTAssertEqual(store.scans[0].frequency, .weekly)
    }
}

final class ScanQuietHoursTests: XCTestCase {
    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testQuietHoursAcrossMidnight() {
        var hours = ScanQuietHours()
        hours.enabled = true
        hours.startMinute = 22 * 60
        hours.endMinute = 7 * 60
        XCTAssertTrue(hours.contains(date(hour: 23)))
        XCTAssertTrue(hours.contains(date(hour: 6, minute: 59)))
        XCTAssertFalse(hours.contains(date(hour: 7)))
        XCTAssertFalse(hours.contains(date(hour: 12)))
    }

    func testQuietHoursDuringDayAndDisabled() {
        var hours = ScanQuietHours()
        hours.startMinute = 9 * 60
        hours.endMinute = 17 * 60
        XCTAssertFalse(hours.contains(date(hour: 10)), "disabled by default")
        hours.enabled = true
        XCTAssertTrue(hours.contains(date(hour: 10)))
        XCTAssertFalse(hours.contains(date(hour: 18)))
        hours.startMinute = hours.endMinute
        XCTAssertFalse(hours.contains(date(hour: 10)), "equal start/end means no quiet window")
    }
}
