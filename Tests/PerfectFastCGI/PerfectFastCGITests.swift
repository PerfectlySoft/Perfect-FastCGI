import XCTest
@testable import PerfectFastCGI

class PerfectFastCGITests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertEqual(PerfectFastCGI().text, "Hello, World!")
    }


    static var allTests : [(String, (PerfectFastCGITests) -> () throws -> Void)] {
        return [
            ("testExample", testExample),
        ]
    }
}
