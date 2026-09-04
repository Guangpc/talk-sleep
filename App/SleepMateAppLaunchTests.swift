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
        XCTAssertTrue(app.staticTexts["创建 AI 好友"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.buttons["导入文字文件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["总结聊天风格与记忆"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.buttons["选择朋友声音"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["创建 AI 好友"].waitForExistence(timeout: 3))
    }

    func testChoosingFriendVoicePresentsDocumentPickerBeforeUploadConsent() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let chooseAudio = app.buttons["friend-audio-import-button"]
        for _ in 0..<4 where !chooseAudio.exists {
            app.swipeUp()
        }
        XCTAssertTrue(chooseAudio.waitForExistence(timeout: 3))
        chooseAudio.tap()

        let cancelButton = app.buttons["取消"]
        let englishCancelButton = app.buttons["Cancel"]
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 3) || englishCancelButton.waitForExistence(timeout: 1),
            "Expected the system document picker to open before upload consent"
        )
    }
}
