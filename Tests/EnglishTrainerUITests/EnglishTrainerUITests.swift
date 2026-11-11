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

    @MainActor func testAccessibilityTextSizeKeepsSpeakingControlsReachable() {
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        openFixture("Could you reschedule the meeting for Thursday?")

        let speakingMode = app.buttons["スピーキング"]
        XCTAssertTrue(speakingMode.waitForExistence(timeout: 5), app.debugDescription)
        speakingMode.tap()
        XCTAssertTrue(app.navigationBars["スピーキング練習"].waitForExistence(timeout: 5))

        let startRecording = app.buttons["録音を開始"]
        scrollTo(startRecording)
        XCTAssertTrue(startRecording.isHittable, startRecording.debugDescription)
        XCTAssertTrue(startRecording.isEnabled, startRecording.debugDescription)
    }

    @MainActor func testSettingsDeleteAllDataOffersConfirmationAndCanBeCancelled() {
        app.launchArguments = ["--uitest-seed-diagnostics"]
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()

        let seededDiagnostics = app.descendants(matching: .any)["diagnostics.uiTestSeedLoaded"]
        for _ in 0..<8 {
            if seededDiagnostics.waitForExistence(timeout: 0.5) { break }
            app.swipeUp()
        }
        XCTAssertTrue(seededDiagnostics.exists)

        let deleteAll = app.buttons["settings.deleteAllData"]
        for _ in 0..<8 {
            if deleteAll.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(deleteAll.isHittable, deleteAll.debugDescription)
        deleteAll.tap()

        let confirm = app.buttons["削除"]
        let cancel = app.buttons["キャンセル"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(cancel.exists, app.debugDescription)
        cancel.tap()

        app.tabBars.buttons["学習"].tap()
        XCTAssertTrue(app.staticTexts["Could you reschedule the meeting for Thursday?"].waitForExistence(timeout: 5))
    }

    @MainActor func testDiagnosticExportRevealsShareActionWithoutOpeningShareSheet() {
        app.launchArguments = ["--uitest-seed-diagnostics"]
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))

        let seededDiagnostics = app.descendants(matching: .any)["diagnostics.uiTestSeedLoaded"]
        scrollTo(seededDiagnostics)

        let createExport = app.buttons["共有用の診断情報を作成"]
        scrollDownTo(createExport)
        createExport.tap()

        let share = app.buttons["診断情報を共有"]
        scrollTo(share)
        XCTAssertTrue(share.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["共有先は次の画面で選びます。記録時刻と識別子、教材・録音・文字起こしは含めません。処理種別や性能値は含まれます。"].exists)
    }

    func testLessonControlsExposeFineSpeechRateAndTranslation() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let lesson = app.staticTexts["Could you reschedule the meeting for Thursday?"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()

        let speechRate = app.sliders["読み上げ速度"]
        XCTAssertTrue(speechRate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["音声を繰り返す"].exists)
        guard let currentRate = Double((speechRate.value as? String ?? "").replacingOccurrences(of: "倍", with: "")) else {
            XCTFail("Could not read the current speaking rate: \(speechRate.debugDescription)")
            return
        }
        let nextRate = currentRate >= 1.5 ? currentRate - 0.05 : currentRate + 0.05
        let currentThumb = speechRate.coordinate(
            withNormalizedOffset: CGVector(dx: currentRate - 0.5, dy: 0.5)
        )
        let nextThumb = speechRate.coordinate(
            withNormalizedOffset: CGVector(dx: nextRate - 0.5, dy: 0.5)
        )
        currentThumb.press(forDuration: 0.1, thenDragTo: nextThumb)
        let fineRateReached = NSPredicate(
            format: "value == %@",
            nextRate.formatted(.number.precision(.fractionLength(2))) + "倍"
        )
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

    @MainActor func testNewLessonPersistsAfterRestart() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        let lesson = "UI test lesson \(UUID().uuidString)"
        let englishField = app.textFields["英文"]
        scrollTo(englishField)
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

    @MainActor func testListeningSelectsPhrase() {
        app.launch()
        openFixture("Could you reschedule the meeting for Thursday?")
        let toggle = app.switches["英文を表示"]
        scrollTo(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let first = app.buttons["lesson.word.0"]
        scrollTo(first)
        first.tap()
        app.buttons["lesson.word.1"].tap()
        let field = app.textFields["単語・フレーズ（空欄で文章全体）"]
        XCTAssertEqual(field.value as? String, "Could you")
    }

    @MainActor private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor private func scrollDownTo(_ element: XCUIElement) {
        for _ in 0..<48 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    @MainActor private func openFixture(_ text: String) {
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        let lesson = app.staticTexts[text]
        scrollTo(lesson)
        lesson.tap()
        XCTAssertTrue(app.navigationBars["リスニング"].waitForExistence(timeout: 5))
    }

    @MainActor func testGeneratedQuestionPersistsAndCorrectionKeepsPriorAnswerHistory() {
        app.launchArguments = ["--uitest-seed-quiz"]
        app.launch()
        let text = "Please confirm your test booking."
        openFixture(text)
        let choice = app.buttons["lesson.choice.1"]
        scrollTo(choice)
        choice.tap()
        let submit = app.buttons["回答を確認"]
        scrollTo(submit)
        submit.tap()
        let result = app.descendants(matching: .any).matching(identifier: "lesson.answerResult").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["正解：The booking"].exists)

        app.terminate()
        app.launch()
        openFixture(text)
        scrollTo(app.buttons["もう一度回答"])
        XCTAssertTrue(result.exists)
        app.buttons["lesson.actions"].tap()
        app.buttons["教材を修正"].tap()
        let question = app.descendants(matching: .any).matching(identifier: "lesson.editor.question").firstMatch
        scrollTo(question)
        question.tap()
        question.typeText(" Check again.")
        app.navigationBars.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["リスニング"].waitForExistence(timeout: 5))
        scrollTo(submit)
        XCTAssertFalse(result.exists)

        app.tabBars.buttons["復習"].tap()
        app.buttons["復習履歴を表示"].tap()
        scrollTo(app.staticTexts["教材を修正する前の回答です。"])
        XCTAssertTrue(app.staticTexts["What should be confirmed?"].exists)
    }

    @MainActor func testLessonIssueAndHiddenStateSurviveRestartAndCanBeRestored() {
        app.launchArguments = ["--uitest-seed-library"]
        app.launch()
        let text = "Please review this library fixture."
        openFixture(text)
        app.buttons["lesson.actions"].tap()
        app.buttons["問題を記録"].tap()
        let note = app.textViews["教材の問題メモ"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        note.typeText("Translation needs a review.")
        app.navigationBars.buttons["保存"].tap()
        app.buttons["lesson.actions"].tap()
        app.buttons["教材を非表示"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        let library = app.buttons["教材を探す・管理"]
        scrollTo(library)
        library.tap()
        let includeHidden = app.switches["非表示の教材も含める"]
        XCTAssertTrue(includeHidden.waitForExistence(timeout: 5))
        includeHidden.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: includeHidden)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        let hidden = app.staticTexts[text]
        scrollTo(hidden)
        hidden.tap()
        app.buttons["lesson.actions"].tap()
        app.buttons["問題を記録"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Translation needs a review.")
        app.navigationBars.buttons["キャンセル"].tap()
        app.buttons["lesson.actions"].tap()
        app.buttons["教材を再表示"].tap()
        app.terminate()
        app.launch()
        openFixture(text)
    }

    @MainActor func testWeakPointReviewAndHistoryPersistAfterRestart() {
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
        let grade = app.buttons["普通"].firstMatch
        scrollTo(grade); grade.tap()
        XCTAssertTrue(app.staticTexts["今日の復習・0件"].waitForExistence(timeout: 5))

        let newExample = app.buttons["新しい用例で復習"].firstMatch
        scrollTo(newExample); newExample.tap()
        XCTAssertTrue(app.navigationBars["新しい用例で復習"].waitForExistence(timeout: 5))
        let phrase = app.descendants(matching: .any).matching(identifier: "review.examplePhrase").firstMatch
        XCTAssertEqual(phrase.value as? String, "reschedule")
        XCTAssertFalse(app.buttons["別の用例を端末内で生成"].isEnabled)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["復習"].tap()
        XCTAssertTrue(app.navigationBars["復習"].waitForExistence(timeout: 5))
        scrollTo(app.buttons["復習履歴を表示"])
        app.buttons["復習履歴を表示"].tap()
        let reviewEvent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "普通 ·")
        ).firstMatch
        XCTAssertTrue(reviewEvent.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reschedule"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["復習"].waitForExistence(timeout: 5))
        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "review.delete.")
        ).firstMatch
        scrollTo(deleteButton)
        XCTAssertTrue(deleteButton.isHittable, app.debugDescription)
        deleteButton.tap()
        let confirmDelete = app.buttons["review.delete.confirm"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), app.debugDescription)
        confirmDelete.tap()
        XCTAssertFalse(app.staticTexts["reschedule"].waitForExistence(timeout: 2))

        let historyLink = app.buttons["復習履歴を表示"]
        scrollTo(historyLink)
        historyLink.tap()
        XCTAssertTrue(app.staticTexts["復習履歴はありません"].waitForExistence(timeout: 5))
    }

    func testSpeakingAndReuseScreensExposeOnDeviceSafetyGates() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        app.staticTexts["Could you reschedule the meeting for Thursday?"].tap()
        XCTAssertTrue(app.navigationBars["リスニング"].waitForExistence(timeout: 5))
        let modeSelector = app.segmentedControls["lesson.modeSelector"]
        XCTAssertTrue(modeSelector.waitForExistence(timeout: 5), app.debugDescription)
        modeSelector.buttons["スピーキング"].tap()

        XCTAssertTrue(app.navigationBars["スピーキング練習"].waitForExistence(timeout: 5))
        modeSelector.buttons["リスニング"].tap()
        XCTAssertTrue(app.navigationBars["リスニング"].waitForExistence(timeout: 5))
        modeSelector.buttons["スピーキング"].tap()
        XCTAssertTrue(app.navigationBars["スピーキング練習"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["音声認識モデル"].exists)
        XCTAssertTrue(app.buttons["ASRモデル管理"].exists)
        XCTAssertTrue(app.staticTexts["文字起こし・評価"].exists)
        XCTAssertFalse(app.buttons["録音を開始"].isEnabled)

        let reuseToggle = app.switches["RE-USEを使う"]
        if !reuseToggle.isHittable { app.swipeUp() }
        XCTAssertTrue(reuseToggle.exists)

        let reuseSettings = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "RE-USEモデルと端末確認の設定")).firstMatch
        if !reuseSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(reuseSettings.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["録音をRE-USEなし／ありで比較"].isEnabled)
        reuseSettings.tap()
        XCTAssertTrue(app.navigationBars["RE-USE設定"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["文字起こしでRE-USEを使用"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "初回ダウンロード後はオフラインで処理できます")).firstMatch.exists)
    }

    @MainActor
    func testTTSListeningNoteSurvivesRestart() {
        app.launchArguments.append("--uitest-seed-tts")
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        let comparison = app.buttons["TTS聴き比べ・性能測定"]
        scrollTo(comparison)
        comparison.tap()
        let add = app.buttons["聴き心地のメモを追加"]
        scrollTo(add)
        add.tap()
        let field = app.descendants(matching: .any).matching(identifier: "tts.listeningNote").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Clear and natural")
        app.buttons["保存"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        scrollTo(comparison); comparison.tap()
        let saved = app.staticTexts["Clear and natural"]
        scrollTo(saved)
        XCTAssertTrue(saved.exists)
        app.buttons["比較メモを編集"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tts.listeningNote").firstMatch.value as? String, "Clear and natural")
    }

    @MainActor func testModelInformationSeparatesUnpreparedFilesAndUnloadedRuntime() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        let information = app.buttons["AIモデル情報・状態"]
        scrollTo(information); information.tap()
        XCTAssertTrue(app.navigationBars["AIモデル情報・状態"].waitForExistence(timeout: 5))
        let kokoro = app.buttons["model.info.kokoro"]
        XCTAssertTrue(kokoro.waitForExistence(timeout: 5)); kokoro.tap()
        XCTAssertTrue(app.staticTexts["hexgrad / FluidInference"].waitForExistence(timeout: 5))
        let unloaded = app.staticTexts["未ロード"]
        scrollTo(unloaded)
        XCTAssertTrue(unloaded.exists)
        XCTAssertTrue(app.staticTexts["未準備"].exists)
        XCTAssertTrue(app.staticTexts["このrevisionの端末生成記録なし。"].exists)
    }

    @MainActor func testASRComparisonRequiresRecordingAndModels() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        let link = app.buttons["ASR聴き取り比較"]
        scrollTo(link); link.tap()
        XCTAssertTrue(app.navigationBars["ASR比較"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["先に教材のスピーキング画面で録音してください。"].exists)
        XCTAssertFalse(app.buttons["2つのASRを比較"].isEnabled)
    }

    @MainActor func testRecordingRetentionSettingPersists() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        let setting = app.switches["recording.retainOnRestart"]
        scrollTo(setting)
        let tapRetentionSwitch = {
            XCTAssertTrue(setting.isHittable, setting.debugDescription)
            setting.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        if setting.value as? String == "0" {
            tapRetentionSwitch()
            expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: setting)
            waitForExpectations(timeout: 5)
        }
        XCTAssertEqual(setting.value as? String, "1")
        tapRetentionSwitch()
        expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: setting)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(setting.value as? String, "0")
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))
        app.tabBars.buttons["設定"].tap()
        scrollTo(setting)
        XCTAssertEqual(setting.value as? String, "0")
        tapRetentionSwitch()
        XCTAssertEqual(setting.value as? String, "1")
    }

    func testASRModelManagementIsReachableFromSettings() {
        app.launch()
        XCTAssertTrue(app.navigationBars["English Trainer"].waitForExistence(timeout: 10))

        app.tabBars.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        let managementLink = app.buttons["ASRモデル管理"]
        XCTAssertTrue(managementLink.waitForExistence(timeout: 5))
        managementLink.tap()

        XCTAssertTrue(app.navigationBars["ASRモデル管理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Parakeet TDT-CTC 110M"].exists)
        let modelSourceLink = app.descendants(matching: .any)
            .matching(identifier: "asr.modelSource").firstMatch
        XCTAssertTrue(modelSourceLink.exists)
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
