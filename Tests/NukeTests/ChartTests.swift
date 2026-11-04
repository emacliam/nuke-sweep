import XCTest
@testable import Nuke

final class ChartTests: XCTestCase {
    func testTreemapConservesAreaAndDoesNotOverlap() {
        let blocks = [60, 25, 10, 4, 1].enumerated().map { StorageBlock(id: "\($0.offset)", name: "Item", size: Int64($0.element), item: nil) }
        let bounds = CGRect(x: 0, y: 0, width: 700, height: 260)
        let tiles = StorageMapLayout.tiles(blocks, in: bounds)
        XCTAssertEqual(tiles.count, blocks.count)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }, bounds.width * bounds.height, accuracy: 0.001)
        for (index, tile) in tiles.enumerated() {
            XCTAssertEqual(tile.rect.width * tile.rect.height / (bounds.width * bounds.height), Double(tile.block.size) / 100, accuracy: 0.000001)
            XCTAssertTrue(bounds.contains(tile.rect))
            for other in tiles.dropFirst(index + 1) {
                let overlap = tile.rect.intersection(other.rect)
                XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 0.00001)
            }
        }
        XCTAssertTrue(StorageMapLayout.tiles([], in: bounds).isEmpty)
    }
    func testTreemapRemainderPreservesAllBytesAndExcludesZeros() {
        let items = (0..<30).map { number in DiskItem(url: URL(fileURLWithPath: "/fixture/\(number)"), size: Int64(number), allocated: 0, directory: false, symlink: false, modified: nil, identity: nil, incomplete: false) }
        let blocks = StorageMapLayout.blocks(items)
        XCTAssertEqual(blocks.count, 25)
        XCTAssertEqual(blocks.reduce(0) { $0 + $1.size }, items.reduce(0) { $0 + $1.size })
        XCTAssertNil(blocks.last?.item)
        XCTAssertEqual(blocks.last?.name, "Other 5 items")
    }
    func testResourceLinesBreakAtMissingSamplesAndLongGaps() {
        let start = Date(timeIntervalSince1970: 1000)
        let samples = [(0.0, 20.0 as Double?), (5, 30), (10, nil), (15, 40), (50, 60)].map { offset, cpu in MonitorSample(disk: ResourceSnapshot(), cpu: cpu, memory: nil, date: start.addingTimeInterval(offset)) }
        let points = ResourceChartPoint.make(samples, memory: false)
        XCTAssertEqual(points.map(\.value), [20, 30, 40, 60])
        XCTAssertEqual(points.map(\.segment), [0, 0, 1, 2])
        XCTAssertTrue(ResourceChartPoint.make(samples, memory: true).isEmpty)
    }
}
