import XCTest
@testable import Nuke

final class StorageForecastTests: XCTestCase {
    func testForecastRequiresSustainedDeclineAndToleratesIsolatedOutlier() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func reading(_ day: Int, _ free: Int64) -> StorageForecast.Reading {
            .init(date: start.addingTimeInterval(Double(day) * StorageForecast.day), free: free * 1_000_000_000,
                  capacity: 100_000_000_000)
        }
        let decline = (0...8).map { reading($0, $0 == 4 ? 90 : Int64(30 - $0)) }
        XCTAssertEqual(StorageForecast.daysRemaining(in: decline, current: reading(8, 22)), 22)
        let oneDrop = (0...8).map { reading($0, $0 < 8 ? 30 : 10) }
        XCTAssertNil(StorageForecast.daysRemaining(in: oneDrop, current: reading(8, 10)))
        XCTAssertNil(StorageForecast.daysRemaining(in: decline, current: reading(14, 16)))
        XCTAssertNil(StorageForecast.daysRemaining(in: Array(decline.prefix(4)), current: reading(3, 27)))
    }
}
