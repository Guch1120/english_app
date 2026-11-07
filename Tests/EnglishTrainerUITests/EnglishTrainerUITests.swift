import XCTest

final class EnglishTrainerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
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
}
