import XCTest

final class SleepMateAppLaunchTests: XCTestCase {
    func testBottomTabsExposeTextAndVoiceDestinations() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let textTab = app.tabBars.buttons["文字与文件"]
        let voiceTab = app.tabBars.buttons["朋友语音"]
        XCTAssertTrue(textTab.waitForExistence(timeout: 3))
        XCTAssertTrue(voiceTab.waitForExistence(timeout: 3))
        voiceTab.tap()
        XCTAssertTrue(app.staticTexts["为 AI 好友添加声音"].waitForExistence(timeout: 3))
        textTab.tap()
        XCTAssertTrue(app.navigationBars["文字与文件"].waitForExistence(timeout: 3))
    }

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

        XCTAssertTrue(app.navigationBars["文字与文件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["创建 AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["导入文字文件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["总结聊天风格与记忆"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["gateway-url-input"].waitForExistence(timeout: 3))
    }

    func testTappingOutsideFriendInputsDismissesKeyboard() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let nameField = app.textFields["friend-name-input"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        app.navigationBars["文字与文件"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        let contextField = app.textViews["friend-context-input"]
        XCTAssertTrue(contextField.waitForExistence(timeout: 3))
        contextField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars["文字与文件"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }

    func testVoiceTabShowsExistingFriendSelectorAndVoicePicker() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let voiceTab = app.tabBars.buttons["朋友语音"]
        XCTAssertTrue(voiceTab.waitForExistence(timeout: 3))
        voiceTab.tap()
        XCTAssertTrue(app.staticTexts["为 AI 好友添加声音"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["切换到文字与文件"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["还没有 AI 好友"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["创建 AI 好友"].exists)
    }

    func testVoiceEmptyStateOffersTextCreationRoute() {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let voiceTab = app.tabBars.buttons["朋友语音"]
        XCTAssertTrue(voiceTab.waitForExistence(timeout: 3))
        voiceTab.tap()
        XCTAssertTrue(app.staticTexts["还没有 AI 好友"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["切换到文字与文件"].waitForExistence(timeout: 3))
        app.buttons["切换到文字与文件"].tap()
        XCTAssertTrue(app.navigationBars["文字与文件"].waitForExistence(timeout: 3))
    }
}
