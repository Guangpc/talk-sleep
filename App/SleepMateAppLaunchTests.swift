import XCTest

final class SleepMateAppLaunchTests: XCTestCase {
    func testLaunchShowsAIFriendEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(app.navigationBars["AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有 AI 好友"].waitForExistence(timeout: 3))
    }
}
