import XCTest

@testable import Musaeum

/// The third kind of local state: the reports the Mac has not taken yet. Each case
/// runs against a temporary directory, so none of them touches the real container.
@MainActor
final class ReportQueueTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("musaeum-reports-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func report(_ bookId: String, _ percent: Double, at seconds: Double = 0) -> ReadingReport {
        ReadingReport(bookId: bookId, percent: percent, readAt: Date(timeIntervalSince1970: seconds))
    }

    /// **AC 2.5.** A report that has waited for the Mac has to survive the phone
    /// being relaunched — that is the only reason the queue is on disk at all.
    func testTheQueueSurvivesARestartInOrder() {
        let queue = ReportQueue(root: root)
        queue.enqueue(report("a", 0.1, at: 100))
        queue.enqueue(report("a", 0.2, at: 200))
        queue.enqueue(report("b", 0.3, at: 300))

        let reopened = ReportQueue(root: root)
        XCTAssertEqual(reopened.reports.map(\.bookId), ["a", "a", "b"])
        XCTAssertEqual(reopened.reports.map(\.percent), [0.1, 0.2, 0.3])
        XCTAssertEqual(reopened.reports.map { $0.readAt.timeIntervalSince1970 }, [100, 200, 300])
        XCTAssertFalse(reopened.isEmpty)
    }

    func testRemovingOneLeavesTheOthers() {
        let queue = ReportQueue(root: root)
        let first = report("a", 0.1)
        let second = report("b", 0.2)
        queue.enqueue(first)
        queue.enqueue(second)

        queue.remove(first.id)
        XCTAssertEqual(queue.reports.map(\.id), [second.id])
        XCTAssertEqual(ReportQueue(root: root).reports.map(\.id), [second.id], "the removal was persisted, not just applied in memory")

        queue.remove(second.id)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertTrue(ReportQueue(root: root).isEmpty)
    }

    /// A fraction is a fraction: the contract's own `0…1`, held at the door rather
    /// than trusted from an engine that rounded.
    func testAReportedFractionIsClampedAtTheQueue() {
        let queue = ReportQueue(root: root)
        queue.enqueue(report("a", 1.4))
        XCTAssertEqual(queue.reports.first?.percent, 1)
    }

    func testAnAbsentIndexIsAnEmptyQueueRatherThanAFailure() {
        let queue = ReportQueue(root: root.appendingPathComponent("never-written"))
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.reports.count, 0)
    }
}
