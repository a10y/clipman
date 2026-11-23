import XCTest
@testable import Clipman

final class RetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private func item(ageDays: Double, bytes: Int) -> ClipItem {
        ClipItem(id: UUID(), date: now.addingTimeInterval(-ageDays * day), kind: .text,
                 preview: "", byteSize: bytes, contentHash: UUID().uuidString,
                 sourceAppName: nil, sourceBundleID: nil,
                 imagePixelWidth: nil, imagePixelHeight: nil, hasThumbnail: false)
    }

    func testEvictsItemsOlderThanMaxAge() {
        let items = [item(ageDays: 0.1, bytes: 1), item(ageDays: 2.9, bytes: 1), item(ageDays: 3.1, bytes: 1)]
        let evicted = Retention.evictions(in: items, now: now, maxAge: 3 * day, maxBytes: 100)
        XCTAssertEqual(evicted, [items[2].id])
    }

    func testEvictsOldestOnceSizeBudgetExceeded() {
        let items = [item(ageDays: 0, bytes: 40), item(ageDays: 0.1, bytes: 40),
                     item(ageDays: 0.2, bytes: 40), item(ageDays: 0.3, bytes: 5)]
        let evicted = Retention.evictions(in: items, now: now, maxAge: 3 * day, maxBytes: 100)
        // Third item overflows; it and everything older go, even the small one.
        XCTAssertEqual(evicted, [items[2].id, items[3].id])
    }

    func testSingleOversizedItemDoesNotWipeHistory() {
        let items = [item(ageDays: 0, bytes: 500), item(ageDays: 0.1, bytes: 10)]
        let evicted = Retention.evictions(in: items, now: now, maxAge: 3 * day, maxBytes: 100)
        XCTAssertEqual(evicted, [items[0].id])
    }

    func testKeepsEverythingWithinLimits() {
        let items = (0..<10).map { item(ageDays: Double($0) * 0.1, bytes: 10) }
        XCTAssertTrue(Retention.evictions(in: items, now: now, maxAge: 3 * day, maxBytes: 100).isEmpty)
    }
}
