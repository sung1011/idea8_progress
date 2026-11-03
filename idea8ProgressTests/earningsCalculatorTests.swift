import XCTest
@testable import idea8Progress

final class EarningsCalculatorTests: XCTestCase {
    func testBusinessRules() throws {
        try EarningsChecks.run()
    }
}
