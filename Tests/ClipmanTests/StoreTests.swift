import AppKit
import XCTest
@testable import Clipman

@MainActor
final class StoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clipman-test-\(UUID())")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func textClip(_ s: String) -> CapturedClip {
        var clip = CapturedClip(payload: ClipPayload(items: [[UTType.plainText: Data(s.utf8)]]),
                                kind: .other, preview: "", contentHash: "")
        clip.contentHash = ClipboardMonitor.hash(clip.payload.items)
        ClipboardMonitor.classify(&clip)
        return clip
    }

    func testDedupesAndBumpsToTop() {
        let store = HistoryStore(directory: dir)
        store.add(textClip("one"))
        store.add(textClip("two"))
        store.add(textClip("one"))
        XCTAssertEqual(store.items.map(\.preview), ["one", "two"])
    }

    func testPersistsAcrossReload() {
        let store = HistoryStore(directory: dir)
        store.add(textClip("hello"))
        XCTAssertEqual(store.payload(for: store.items[0])?.plainText, "hello")

        let reloaded = HistoryStore(directory: dir)
        XCTAssertEqual(reloaded.items.map(\.preview), ["hello"])
        XCTAssertEqual(reloaded.items[0].kind, .text)
    }

    func testRoundTripsThroughPasteboard() {
        let store = HistoryStore(directory: dir)
        store.add(textClip("round trip"))
        let pb = NSPasteboard(name: .init("clipman-test-\(UUID())"))
        defer { pb.releaseGlobally() }
        XCTAssertTrue(store.writeToPasteboard(store.items[0], pasteboard: pb))
        XCTAssertEqual(pb.string(forType: .string), "round trip")
    }
}
