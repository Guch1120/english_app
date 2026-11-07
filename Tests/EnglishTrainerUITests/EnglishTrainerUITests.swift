import XCTest

final class EnglishTrainerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "jp.guch1120.EnglishTrainer")
    }

    func testTopLevelTabsOpenTheirPrimaryScreens() {
        app.launch()

        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let reviewTab = app.tabBars.buttons["復習"]
        XCTAssertTrue(reviewTab.waitForExistence(timeout: 5))
        reviewTab.tap()
        XCTAssertTrue(app.navigationBars["復習"].waitForExistence(timeout: 5))

        let settingsTab = app.tabBars.buttons["設定"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["音声とAI"].exists)
    }

    func testLessonControlsExposeFineSpeechRateAndTranslation() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let lesson = app.staticTexts["Could you reschedule the meeting for Thursday?"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()

        let speechRate = app.sliders["読み上げ速度"]
        XCTAssertTrue(speechRate.waitForExistence(timeout: 5))
        speechRate.adjust(toNormalizedSliderPosition: 0.55)
        XCTAssertEqual(speechRate.value as? String, "1.05倍")

        let translationToggle = app.switches["日本語訳を表示"]
        XCTAssertTrue(translationToggle.exists)
        translationToggle.tap()
        XCTAssertEqual(translationToggle.value as? String, "1")
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["会議を木曜日に変更していただけますか？"].waitForExistence(timeout: 5),
            app.debugDescription
        )
    }

    func testNewLessonPersistsAfterRestart() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let lesson = "UI test lesson \(UUID().uuidString)"
        let englishField = app.textFields["英文"]
        XCTAssertTrue(englishField.waitForExistence(timeout: 5))
        englishField.tap()
        englishField.typeText(lesson)
        app.buttons["教材を追加"].tap()
        XCTAssertTrue(app.staticTexts[lesson].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[lesson].waitForExistence(timeout: 5))
    }

    func testWeakPointReviewAndHistoryPersistAfterRestart() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let lesson = app.staticTexts["Could you reschedule the meeting for Thursday?"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()

        let revealEnglish = app.switches["英文を表示"]
        XCTAssertTrue(revealEnglish.waitForExistence(timeout: 5))
        revealEnglish.tap()
        let weakPointField = app.textFields["単語・フレーズ（空欄で文章全体）"]
        XCTAssertTrue(weakPointField.waitForExistence(timeout: 5))
        weakPointField.tap()
        weakPointField.typeText("reschedule\n")
        app.buttons["復習に登録"].tap()
        XCTAssertTrue(app.buttons["保存しました"].waitForExistence(timeout: 5))

        let reviewTab = app.tabBars.buttons["復習"]
        XCTAssertTrue(reviewTab.waitForExistence(timeout: 5))
        reviewTab.tap()
        XCTAssertTrue(app.navigationBars["復習"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["reschedule"].waitForExistence(timeout: 5))
        app.buttons["普通"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["今日の復習・0件"].waitForExistence(timeout: 5))

        app.buttons["復習履歴を表示"].tap()
        let reviewEvent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "普通 ·")
        ).firstMatch
        XCTAssertTrue(reviewEvent.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        reviewTab.tap()
        app.buttons["復習履歴を表示"].tap()
        XCTAssertTrue(reviewEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reschedule"].exists)
    }
}
