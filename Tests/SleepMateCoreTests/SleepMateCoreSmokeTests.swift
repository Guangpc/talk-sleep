import XCTest
@testable import SleepMateCore

final class SleepMateCoreSmokeTests: XCTestCase {
    func testPackageExposesVersion() {
        XCTAssertEqual(SleepMateCore.version, "0.1.0")
    }
}
