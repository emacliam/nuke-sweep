import XCTest
import NukeMetrics
@testable import Nuke

final class WidgetMetricsTests: XCTestCase {
    func testStorageFractionClampsAndUnavailableStaysUnknown() {
        XCTAssertEqual(WidgetMetrics(totalDisk: 100, freeDisk: 25, cpu: nil, memory: nil).usedFraction, 0.75)
        XCTAssertEqual(WidgetMetrics(totalDisk: 100, freeDisk: 150, cpu: nil, memory: nil).usedFraction, 0)
        XCTAssertNil(WidgetMetrics.placeholder.usedFraction)
        XCTAssertNil(WidgetMetrics(totalDisk: 0, freeDisk: 0, cpu: nil, memory: nil).usedFraction)
        XCTAssertEqual(WidgetMetrics(totalDisk: Int64.max, freeDisk: Int64.min, cpu: nil, memory: nil).usedFraction, 1)
    }
    func testSharedMetricsKeepUnknownReadingsThroughEncoding() throws {
        let snapshot = WidgetMetrics(totalDisk: 100, freeDisk: 20, cpu: nil, memory: nil)
        let restored = try JSONDecoder().decode(WidgetMetrics.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored, snapshot)
        XCTAssertNil(restored.cpu); XCTAssertNil(restored.memory)
    }
    func testCounterWrapAndNoTickSample() {
        XCTAssertEqual(SystemMetrics.utilization(before: [UInt64(UInt32.max) - 4, 0, 100, 0], after: [5, 0, 110, 0]), 50)
        XCTAssertNil(SystemMetrics.utilization(before: [0, 0, 0, 0], after: [0, 0, 0, 0]))
        XCTAssertNil(SystemMetrics.utilization(before: [UInt64.max, 0, 0, 0], after: [0, 0, 0, 0]))
    }
    func testStatusBarDoesNotShowZeroForUnavailableStorage() {
        let sample = MonitorSample(disk: ResourceSnapshot(), cpu: nil, memory: nil, date: Date())
        XCTAssertEqual(StatusBarMetric.storage.reading(sample), "Storage —")
        XCTAssertEqual(StatusBarMetric.cpu.reading(sample), "CPU —")
        XCTAssertEqual(StatusBarMetric.memory.reading(sample), "VM —")
        XCTAssertNil(StatusBarMetric.icon.reading(sample))
    }
    func testStatusBarReadsTheChosenMetric() {
        var disk = ResourceSnapshot(); disk.totalDisk = 100_000_000_000; disk.freeDisk = 25_000_000_000
        let sample = MonitorSample(disk: disk, cpu: 42, memory: 4_000_000_000, date: Date())
        XCTAssertEqual(StatusBarMetric.cpu.reading(sample), "CPU 42%")
        XCTAssertTrue(StatusBarMetric.storage.reading(sample)?.contains("25") == true)
        XCTAssertTrue(StatusBarMetric.memory.reading(sample)?.contains("VM") == true)
    }
    func testSharedSystemStorageMatchesHostService() throws {
        let disk = try SystemMetrics.storage()
        XCTAssertGreaterThan(disk.total, 0)
        XCTAssertGreaterThanOrEqual(disk.free, 0)
        XCTAssertLessThanOrEqual(disk.free, disk.total)
        XCTAssertEqual(MachineService.snapshot().totalDisk, disk.total)
    }
}
