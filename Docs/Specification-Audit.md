# 仕様照合と未完了項目（2026-11-11、main app code 22438f4／latest UI test PR #124 merge 0461132／latest acceptance docs PR #128 merge 224200e）

Phase 0〜7と仕様本文の追加機能をmain app code baseline `22438f4`、UI test merge `0461132`、PR履歴、CI結果、TestFlight実機証拠と照合した。実装済み、CIで確認した項目、実機未確認を分けて記録する。利用者の実機確認と未確認項目は[Acceptance.md](Acceptance.md)を参照。PR #117のValidate run 42935927652ではquality、Docker Core、macOS package、Simulator build/analyze/launch、16件のUI tests、unsigned archive、review-gateがすべて成功し、診断エクスポートの共有導線と開示文をSimulatorで確認した（share sheetは開いていない）。PR #124のValidate run 42953378383ではquality、Docker Core、macOS package、Simulator build/analyze/launch、17件のUI tests、unsigned archive/dSYM、review-gateがすべて成功し、大型文字の操作到達性をSimulatorで確認した。Docker `bash Scripts/test.sh`は46件、`bash Scripts/quality.sh`は18件のpolicy testとshellcheck/actionlint/Gitleaks/vendor snapshot checksが成功した。TestFlight run 42917141650は0.1.0 (208.1)をアップロードし、iPhone 16へ導入後の起動確認も成功した。208.1実機でGemma 4 E2Bの2.59 GB候補を取得・SHA-256検証し固定prompt推論に成功後、新規候補だけ削除し既存GPUモデルを保持した。

## Phase 0〜7後に追加した仕様項目

| 仕様 | 実装・根拠 | 残る確認 |
|---|---|---|
| §10.3 フレーズ選択 | PR #54で連続した複数語を復習項目にできる | 実機で操作性を確認 |
| §14.2 同一録音のASR比較 | PR #58で保存した一つの録音をParakeet/Apple Speechに順番に入力し、比較結果を表示。2026-11-11に保持設定ONでのアプリ再起動後、保存録音3.9秒を再認識し、画面のWERはParakeet 57%／Apple Speech 0%。同じ録音で機内モードON・Wi-Fi OFF中も両方の結果表示を確認。本文は取得・確認していない | WERの文字列レベル検算、別録音での再現性、取消・再試行 |
| §13.3・§14.2 録音保持 | PR #58で保持を既定とし、無効化時は次回起動時に削除。2026-11-11にiPhone 16／208.1で保持ONのままアプリを再起動後、Speaking画面に保存録音3.9秒が残ることを確認。録音内容にはアクセスせず、変更・削除なし | 保持OFF時の次回起動削除、既存データを含む旧buildからの実機アップグレード |
| §15.3 診断情報エクスポート | PR #53で固定項目のみの診断共有を実装。PR #117のValidate run 42935927652でSimulator UIからレポートを作り、共有ボタンと開示文を確認。iPhone 16／208.1でWDAからshare sheet表示・dismissを確認。音声・文字起こしは含めない | 共有先選択・実送信は未確認。レポートは送信していない |
| §18.2 バックグラウンド再生 | PR #56でシステム音声、ニューラルTTS、保存録音の再生ライフサイクルを実装。Kokoroの再生中にHomeへ移動後もプロセス（PID 4457）が存在。2026-11-11にiPhone 16／iOS 26.4.2／208.1で繰り返しONのKokoro比較音声とApple（米国英語）のお手本音声を別々に再生し、利用者が各々サイドボタンでロック後も音が続くと確認。試験後にWDAで再生を停止し、Kokoro選択・repeat OFFへ復帰。 | Home移動後の実聴、保存録音のロック・背景再生、音声割り込み、音声経路喪失、長時間挙動 |
| Apple Speech 録音開始時クラッシュ | PR #57でauthorization callbackをMainActor隔離の外に移動。145.1で報告されたクラッシュを対象とした。160.1のiPhone 16でApple Speech選択後の録音開始・停止、アプリ継続を確認。指定英文の録音とApple Speech結果表示を後続buildで確認 | 英語実音声の反復精度。権限拒否後の再試行は利用者の希望で試験を見送り、未確認 |
| §6.3 全TTSの繰り返し再生 | PR #60でApple synthesizerの完了delegateによるrepeat loopを追加。ニューラル音声を含め全engineにtoggleを適用 | 208.1でKokoro repeatを2回聴取し、repeat ONのロック後再生も確認。Apple音声はロック後再生を確認したが、Apple repeatは未確認 |
| §15.1 LLM decode tokens/sec | PR #60でLiteRT-LM 0.19.1の`Conversation.getBenchmarkInfo()`を用い、実測デコード速度が返る場合のみ表示。実験APIを明示opt-in | 160.1でload 1.5秒、TTFT 0.8秒、生成4.8秒、43.1 tokens/sec、process RSS 572.3 MBを一回観測。反復性能・熱比較は未確認 |

## 仕様本文の照合

| 仕様 | 実装・証拠 | 残る確認 |
|---|---|---|
| §5 共通AI操作・モデル情報 | 共通サービスprotocol、モデル情報、検証付きダウンロード、排他実行、cancel/unload。キャンセル済みタスクをlease競合より先に判定し、実行中ASR backendへcancelを伝える修正をPR #110で実装。Validate run 42907001478の必須CIが全件成功。201.1オフライン準備画面でTTS/ASR/LLM/RE-USEの端末状態を確認。Model-Information.md参照 | iPhone実機のASR中断・復帰。ParakeetのFluidAudio TDT推論はAPI上、進行中計算を同期停止できず、呼び出し復帰後にキャンセル結果を破棄してアンロードする |
| §6 TTS | Kokoro、Pocket TTS、Apple音声、話者選択、再生制御、全engine repeat、速度、キャッシュ、比較、生成時間/RTF/RSS/音声長/サンプルレート、主観メモを実装。160.1のオフライン計測をAcceptance.mdに記録。repeat switchをOFFからONへ操作し、Kokoroを2回再生して両方聞こえたと利用者が確認。Pocket TTSも利用者が正常動作を確認 | 中断・音声経路変更、長時間安定性、専門的な発音・音質評価。iOS 26.4.2ではCoreDevice音声ストリームは非対応 |
| §7 ASR | Parakeetと端末内Apple Speech、録音、再認識、同一録音比較。143.1でParakeetの録音・文字起こし画面を確認。160.1でApple Speech選択後の録音・文字起こしを確認。指定英文による3.9秒再録音で両エンジンの結果表示を確認し、画面上でApple Speech WER 0%／0.13秒／178.5 MB、Parakeet WER 57%／0.03秒／179 MBを表示。利用者は「両方一致」は両方から結果が出た意味と訂正した。文字起こし本文を独立に確認していないため、WER値はアプリ表示として記録し、利用者による文字列一致確認とは扱わない。同じ録音をParakeetで再認識した2回目もWER 57%を表示したが、文字列の一致や別録音での再現性を示すものではない。2026-11-11にiPhone 16／208.1で機内モードON・Wi-Fi OFF中、保持済み3.9秒録音のParakeet/Apple Speech双方で結果を再表示。WER表示は57%／0%のまま。本文は未確認で、オフライン動作の確認であり精度検証ではない。Apple Speech録音3.863秒、単独認識184 ms／186.2 MBも診断で成功。音声ファイルは端末内に保持し、本文は保存・共有しない | Parakeetの誤り原因・別録音での再現性、文字列の反復一致、権限拒否後の再試行、ASR取消・中断回復 |
| §8 RE-USE | 任意設定、固定音声による端末検証gate、5分上限、元音声保持、ASRによる比較を実装。同梱固定音声を機内モードで比較し、RE‑USE処理3.02秒／RTF 0.278／モデルload1.87秒／MLX peak1.01 GB／process RSS peak452.5 MB。さらにiPhone 16／160.1で利用者の3.9秒録音をApple Speechにより比較し、両経路の結果表示を確認。処理1.24秒／RTF 0.321／model load0.14秒／MLX peak1.39 GB、認識時間はなし0.16秒／あり0.13秒。設定をOFFに戻し、元録音は保持 | 各結果のWER差、実聴での明瞭さ・学習上の効果、反復性能・熱挙動 |
| §9 LLM | Gemma 4 E2B教材生成、構造/難易度/日本語存在gate、教材編集、問題メモ、非表示、弱点から新しい用例を生成。160.1でオンライン/機内モード中の教材生成に成功し、オフライン生成直後のプロセス再起動後も保存一覧から復元。190.1の実機検索で9候補のmetadataを確認。208.1で2.59 GB候補（Apache-2.0、revision `3d48132a`）を実機取得しSHA-256検証と固定prompt推論に成功。新規候補だけ削除し、既存2.01 GB GPUモデルと選択を保持・復元 | 実機教材の意味品質、別候補互換性、異なる条件・熱状態での反復性能 |
| §10 学習画面 | 再生・速度・原文表示切替・復習登録、カテゴリ/難易度/Part検索、フレーズ選択、弱点からの新規用例、教材移動。PR #94で復習項目の削除導線を分離。190.1の実機でサンプル教材からの単語選択・復習登録を確認。PR #124でAccessibility XXXL時のSpeaking操作到達性をSimulator UI testで確認。2026-11-11にiPhone 16／208.1でもLarger Text ON・100%でSpeakingの長文折り返しと、スクロール後の保存録音操作ボタン表示を確認し、設定をOFF・50%へ復帰 | VoiceOver、片手操作、実際の録音ボタン操作。実機確認はアクセシビリティ表示とボタンの表示まで |
| §11 スピーキング | お手本再生、録音、文字起こし比較、単語差分/WERと正規化 | 実機での録音中断・機内モード。厳密な音素/発音採点は初期要件外 |
| §12 復習 | 決定的スケジューラ、履歴、習熟度、教材versionと回答記録。PR #94のSimulator UIテストと190.1実機で履歴保持・削除cascadeを確認。2026-11-10に「普通」で成功1/失敗0、習熟度100%、2日後予定を確認。2026-11-11は機内モードON・Wi‑Fi OFF中に同じ評価を行い、SIGKILL・再起動後も回答イベントと予定が残ることを確認。両試験項目・履歴は削除済み | 他の評価段階、長期予定推移、旧buildからのデータ移行 |
| §13 保存 | SQLite transaction、保護領域、schema migration、教材と回答履歴。208.1実機で録音保持トグルON（値1）と、アプリ再起動後もSpeaking画面に保存録音3.9秒が残ることを確認 | 古いデータからの実機アップグレード・復元、録音保持OFF時の次回起動削除 |
| §14 UI | 学習、復習、設定、モデル管理と診断の各画面。PR #105で設定のデータ領域を診断一覧より上へ移し、明示キャンセル付き確認alertを追加。GitHub macOS Validate run 42888324021で15件のSimulator UI testが成功し、iPhone 16／201.1でもデータ削除導線が診断履歴より上にあり、確認alertのキャンセルで閉じることを確認。PR #124のrun 42953378383ではAccessibility XXXL設定でSpeakingの録音開始コントロールまでスクロールし、hittableであることをSimulator UI testで確認。208.1実機ではLarger Text ON・100%設定でSpeaking画面の長文折り返しと、スクロール後の録音操作ボタン表示を確認し、設定をOFF・50%へ復元。208.1のインストール後起動もDocker USB検証済み | VoiceOver、片手操作、実機のコントロールhittable/tap確認。実機での破壊的な全データ削除は未実施 |
| §15 診断 | 固定fieldの端末内ログ、共有用エクスポート、TTS/ASR/RE-USE計測、LLM TTFT/デコードtokens/sec。RSSはプロセス全体の観測値として表示 | 異なる条件・熱状態での反復測定、診断共有確認。RSSをモデル単体メモリと解釈しない |
| §16 安全性 | 学習データと音声は端末内。通常ログに音声/文字起こしを出さず、model binaryや署名情報をGitに含めない | 変更ごとの継続的なdiff/secret review |
| §17 CI/CD | PR #105のフル Validate [run 42888324021](https://github.com/Guch1120/english_app/actions/runs/42888324021)でquality、Docker Core、GitHub macOS package/Simulator UI 15件/unsigned archive/review-gate成功。PR #105は`aa9fe44`でマージ。TestFlight upload [run 42897334281](https://github.com/Guch1120/english_app/actions/runs/42897334281)成功し、201.1をアップロード・実機導入。PR #106は`f6c7903`、PR #107は`d0febd3`、PR #108は`7021b2e`、PR #109は`6481762`、PR #110は`25ddb31`、PR #111は`c1f4156`、PR #112は`18fa3b6`、PR #113は`1b63026`、PR #124は`0461132`でマージ。run 42901278396・42902332632・42904366798・42905343196・42907001478・42953378383は各対象check成功。#124 runではquality、Docker Core 46 tests、macOS package、Simulator build/analyze/launch、17 UI tests、unsigned archive/dSYM、review-gateが成功。TestFlight run 42917141650は208.1を正常アップロードし、device verifyをDockerで実行した | PR #110変更のiPhone ASR中断動作、新しいbuildでの総合回帰、残りの実機受け入れ |
| §18 実機 | iPhone 16/iOS 26.4.2でTestFlight 208.1を導入。Docker USB queryでbuildを確認し、起動後もPID 4313で稼働、appLaunch診断イベント1件、RSS peak 110,018,560 bytes、thermal nominalを確認。Gemma 2.59 GB candidate download/SHA-256/fixed inference/deletionも完了し、既存GPU候補は保持。設定でデータ削除導線の順序と確認alertのキャンセル、オフライン準備画面の内容も確認済み（201.1）。従来のTTS/ASR/RE-USE/Gemma/review実機証拠はAcceptance.mdを参照 | Parakeet別録音の精度・再現性、RE-USEのWER差・実聴効果、LLM意味品質、再生中断・画面ロック・バックグラウンド音声、長時間・熱挙動。Bluetooth経路は利用者の希望により未試験で、通常利用で問題が出た場合に調査する |

## 完了判定

自動CIが通過したコード実装と、物理iPhone上で未確認の受け入れ項目は別である。PR #94はquality、Core、macOS package、iOS Simulator UI、unsigned archive、review-gateが成功してmainへマージ済みで、復習履歴の再起動保持と削除cascadeをSimulatorで確認した。TestFlight run 42825893942で190.1をアップロードし、TestFlight表示とiPhone 16への導入を確認した。2026-11-10の実機確認ではレビュー回答・2日後予定・履歴表示、試験項目のcascade削除後に保存済み0件・既存学習操作履歴保持を確認した。2026-11-11はWi‑Fi OFFと機内モードONを設定画面で確認してからレビュー項目を登録・回答し、SIGKILL・再起動後も回答・次回予定・履歴が保持されることを確認した後、その項目と履歴だけを削除した。機内モードOFF・Wi‑Fi ONと接続中ネットワークを再確認した。PR #66をDocker testsとGitHub macOS CI成功後にmainへマージし、TestFlight 160.1をiPhone 16へ導入した。190.1ではGemmaモデル検索から9候補のサイズ・ライセンス・revision表示を確認し、モデルファイルの取得・削除は行わなかった。160.1ではオンライン/機内モード中のGemma教材生成と保存復元、機内モード・Wi‑Fi OFF中のKokoro/Pocket TTS生成、固定サンプルによるParakeet/Apple Speech認識とRE‑USE比較を確認した。追加の実機確認ではKokoro repeat再生が2回聞こえ、依頼した英文を録音した利用者所有音声で両ASRの結果表示を確認した。画面上のWER表示はApple Speech 0%、Parakeet 57%。利用者は「両方一致」は両方から結果が出た意味と訂正し、文字起こし本文を独立に確認していないため、文字列一致の利用者確認とは扱わない。同じ録音のParakeet再認識でもWER 57%だったが、別音声での再現性や文字列レベルの一致を確立しない。保存した同じ3.9秒音声でApple SpeechとRE‑USEの比較も行い、両経路の認識時間とRE‑USE処理時間・メモリを観測したが、各WER差を保存しておらず、音の明瞭さも未評価。208.1をTestFlightから導入し、Docker USB検証で起動・固定fieldの起動診断イベント1件・RSS 110,018,560 bytes・thermal nominalを確認した。これは新buildの短時間起動確認であり、音声・モデル・長時間挙動を再検証したものではない。LLM意味品質、バックグラウンド再生、割り込み、反復性能・熱挙動などが残るため、アプリ全体の実機受け入れ完了とは扱わない。試験後、RE‑USE設定OFF、機内モードOFF、Wi‑Fi接続を再確認した。

## 追加の全章ソース照合

| 仕様 | 現在の実装根拠 | 状態と限界 |
|---|---|---|
| §1 目的・基本方針 | SwiftUI学習アプリ、端末内SQLiteとPackage分割。クラウド推論・同期・認証を持たない | ローカルファースト設計は実装済み。全ての端末条件での実機受け入れは継続中 |
| §2 対象端末・技術 | Xcode deployment targetはiOS 18.0。基準端末iPhone 16、確認OSはiOS 26.4.2 | 実機操作を確認。最低OS実機と空きストレージ量は未測定 |
| §3 参照プロジェクト | upstreamコード・SDK・モデルの利用箇所とrevision/licenseをcomponent docsへ記録 | 参照プロジェクトは変更していない。依存追加時はAPIと各モデル重みの条件を再確認 |
| §4 アーキテクチャ | LearningCore/LearningPersistenceとSpeechCore・各推論backendがSwift Packageで分離され、SwiftUI層から学習スケジューリングを独立 | Package testとmacOS compileで確認。別アプリからの再利用は未検証 |
| §19 開発フェーズ | Phase 0〜7と安定化の実装PRはmainへマージ済み。mainに未完了PRはない | 実装フェーズ完了と実機受け入れ完了は別。仕様で必要な端末確認は残る |
| §20 初期版の完了条件 | 18条件を[Acceptance.md](Acceptance.md)の表で個別追跡 | CI、TestFlight、複数の実機フローを確認したが、全条件はまだ受け入れ完了ではない。Bluetoothは利用者の希望により通常利用で問題が出た場合の調査へ延期 |
| §21 対象外 | クラウド推論、同期、リアルタイム会話、ロボット接続、厳密な発音採点、一般公開はv1対象外 | 未実装として扱い、対応済みと表示していない |
| §22 開発指示 | AGENTS.mdのDocker、GitHub macOS、codex branch/PR、秘匿、license要件に従う | PR #105はフルDocker/macOS Validate成功後にマージ。PR #106〜#108はquality/review-gate成功後にマージ。今後の変更も同じ運用にする |
| §23 参考資料 | TTS/ASR/RE-USE/LLMのcomponent docsにupstream資料と採用revisionを記録 | upstream情報は変わり得るため、変更時に再確認 |

利用者はRE-USEの主観音質比較を「実聴なしで記録」と指定した。その項目は未評価として残し、初期版の完了条件を満たした証拠には数えない。
