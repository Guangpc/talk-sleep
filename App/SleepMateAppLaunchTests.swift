import XCTest

final class SleepMateAppLaunchTests: XCTestCase {
    func testLaunchShowsAIFriendEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        _ = addUIInterruptionMonitor(withDescription: "microphone permission") { alert in
            for title in ["允许", "好", "Allow", "OK"] {
                if alert.buttons[title].exists {
                    alert.buttons[title].tap()
                    return true
                }
            }
            return false
        }
        app.launch()

        XCTAssertTrue(app.navigationBars["AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有 AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["开始真机语音测试"].waitForExistence(timeout: 3))
    }
}
