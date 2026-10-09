import XCTest

@testable import Musaeum

/// Which file the phone asks for. The rule trusts the Mac's `reflow.available`; it does not re-derive it from `formats`.
final class DownloadPlanTests: XCTestCase {
    private func book(formats: [String], reflow: Bool) throws -> ContractBook {
        let url = try XCTUnwrap(Bundle(for: DownloadPlanTests.self).url(forResource: "book", withExtension: "json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["formats"] = formats
        object["reflow"] = ["available": reflow]
        return try JSONDecoder().decode(ContractBook.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testReflowAvailableAsksForTheReflow() throws {
        XCTAssertEqual(DownloadPlan.of(try book(formats: ["pdf"], reflow: true)), .reflow)
    }

    func testReflowAvailableWinsOverTheWireOrder() throws {
        XCTAssertEqual(DownloadPlan.of(try book(formats: ["mobi", "pdf"], reflow: true)), .reflow)
    }

    func testNoReflowAsksForTheFirstFormat() throws {
        XCTAssertEqual(DownloadPlan.of(try book(formats: ["epub", "pdf"], reflow: false)), .format("epub"))
    }

    /// `available` is eligibility, so a PDF the Mac does not offer to reflow is the pre-slice case.
    func testAPdfWithoutReflowStaysAPdf() throws {
        XCTAssertEqual(DownloadPlan.of(try book(formats: ["pdf"], reflow: false)), .format("pdf"))
    }

    func testNothingToAskForIsNil() throws {
        XCTAssertNil(DownloadPlan.of(try book(formats: [], reflow: false)))
    }
}
