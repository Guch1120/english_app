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
        let currentRate = speechRate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let fineRate = speechRate.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        currentRate.press(forDuration: 0.1, thenDragTo: fineRate)
        let fineRateReached = NSPredicate(format: "value == %@", "1.05倍")
        let fineRateExpectation = XCTNSPredicateExpectation(predicate: fineRateReached, object: speechRate)
        XCTAssertEqual(XCTWaiter.wait(for: [fineRateExpectation], timeout: 5), .completed, speechRate.debugDescription)

        let translationToggle = app.switches["日本語訳を表示"]
        XCTAssertTrue(translationToggle.exists)
        if !translationToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(translationToggle.isHittable, translationToggle.debugDescription)
        translationToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let translationEnabled = NSPredicate(format: "value == %@", "1")
        let translationExpectation = XCTNSPredicateExpectation(predicate: translationEnabled, object: translationToggle)
        XCTAssertEqual(XCTWaiter.wait(for: [translationExpectation], timeout: 5), .completed)
        let translation = app.staticTexts["会議を木曜日に変更していただけますか？"]
        if !translation.exists { app.swipeUp() }
        XCTAssertTrue(
            translation.waitForExistence(timeout: 5),
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

    func testSpeakingAndReuseScreensExposeOnDeviceSafetyGates() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        app.staticTexts["Could you reschedule the meeting for Thursday?"].tap()
        XCTAssertTrue(app.navigationBars["リスニング"].waitForExistence(timeout: 5))
        let lessonForm = app.collectionViews.firstMatch
        XCTAssertTrue(lessonForm.waitForExistence(timeout: 5))
        let speakingLink = app.descendants(matching: .any)
            .matching(identifier: "lesson.speakingPractice").firstMatch
        for _ in 0..<4 where !speakingLink.exists { lessonForm.swipeUp() }
        XCTAssertTrue(speakingLink.waitForExistence(timeout: 5), app.debugDescription)
        speakingLink.tap()

        XCTAssertTrue(app.navigationBars["スピーキング練習"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["音声認識モデル"].exists)
        XCTAssertTrue(app.buttons["Parakeetモデルをダウンロード"].exists)
        XCTAssertFalse(app.buttons["録音を開始"].isEnabled)

        let reuseToggle = app.switches["RE-USEを使う"]
        if !reuseToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(reuseToggle.exists)

        let reuseSettings = app.buttons["RE-USEモデルと端末確認の設定"]
        if !reuseSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(reuseSettings.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["録音をRE-USEなし／ありで比較"].isEnabled)
        reuseSettings.tap()
        XCTAssertTrue(app.navigationBars["RE-USE設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["比較機能でRE-USEを使用"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "初回ダウンロード後はオフラインで処理できます")).firstMatch.exists)
    }

    func testLLMGenerationRequiresVerifiedModelAndOpensModelManager() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        let generationLink = app.buttons["LLM教材生成・モデル管理"]
        XCTAssertTrue(generationLink.waitForExistence(timeout: 5))
        generationLink.tap()

        XCTAssertTrue(app.navigationBars["教材を生成"].waitForExistence(timeout: 5))
        let generateButton = app.buttons["端末内で教材を生成"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 5))
        XCTAssertFalse(generateButton.isEnabled)
        XCTAssertTrue(app.staticTexts["未確認のLLMは教材生成に使えません。モデルを準備してから、端末上の固定テストを実行してください。"].exists)

        app.buttons["モデル検索・管理"].tap()
        XCTAssertTrue(app.navigationBars["LLMモデル管理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Gemma 4を探す"].exists)
    }
}
