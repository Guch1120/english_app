# 仕様照合と未完了項目（2026-11-10）

Phase 0〜7と、それらのPRで扱った仕様本文の追加機能をmainのコードおよびCI結果と照合した。実装済み、CIで確認した項目、実機未確認を分けて記録する。利用者の実機確認と未確認項目は[Acceptance.md](Acceptance.md)を参照。

## Phase 0〜7後に追加した仕様項目

| 仕様 | 実装・根拠 | 残る確認 |
|---|---|---|
| §10.3 フレーズ選択 | PR #54で連続した複数語を復習項目にできる | 実機で操作性を確認 |
| §14.2 同一録音のASR比較 | PR #58で保存した一つの録音をParakeet/Apple Speechに順番に入力し、比較結果を表示 | 実機の認識品質、取消・再試行 |
| §13.3・§14.2 録音保持 | PR #58で保持を既定とし、無効化時は次回起動時に削除 | 設定変更・再起動後の実機挙動 |
| §15.3 診断情報エクスポート | PR #53で固定項目のみの診断共有を実装。音声・文字起こしは含めない | 実機で共有シートと出力を確認 |
| §18.2 バックグラウンド再生 | PR #56でシステム音声、ニューラルTTS、保存録音の再生ライフサイクルを実装 | 画面ロック、割り込み、音声経路喪失の実機確認 |
| Apple Speech 録音開始時クラッシュ | PR #57でauthorization callbackをMainActor隔離の外に移動。145.1で報告されたクラッシュを対象とした。160.1のiPhone 16でApple Speech選択後の録音開始・停止、アプリ継続を確認。無音入力の文字起こしは失敗 | 英語実音声の文字起こし品質、権限拒否後の再試行 |
| §6.3 全TTSの繰り返し再生 | PR #60でApple synthesizerの完了delegateによるrepeat loopを追加。ニューラル音声を含め全engineにtoggleを適用 | TestFlight 154.1以降でApple/ニューラル双方の繰り返し・停止・画面ロックを確認 |
| §15.1 LLM decode tokens/sec | PR #60でLiteRT-LM 0.19.1の`Conversation.getBenchmarkInfo()`を用い、実測デコード速度が返る場合のみ表示。実験APIを明示opt-in | 160.1でload 1.5秒、TTFT 0.8秒、生成4.8秒、43.1 tokens/sec、process RSS 572.3 MBを一回観測。反復性能・熱比較は未確認 |

## 仕様本文の照合

| 仕様 | 実装・証拠 | 残る確認 |
|---|---|---|
| §5 共通AI操作・モデル情報 | 共通サービスprotocol、モデル情報、検証付きダウンロード、排他実行、cancel/unload。Model-Information.md参照 | 実機のロード状態・失敗回復 |
| §6 TTS | Kokoro、Pocket TTS、Apple音声、話者選択、再生制御、全engine repeat、速度、キャッシュ、比較、生成時間/RTF/RSS/音声長/サンプルレート、主観メモを実装。160.1のオフライン計測をAcceptance.mdに記録。repeat switchをOFFからONへ操作し、Kokoroを2回再生して両方聞こえたと利用者が確認。Pocket TTSも利用者が正常動作を確認 | 中断・音声経路変更、長時間安定性、専門的な発音・音質評価。iOS 26.4.2ではCoreDevice音声ストリームは非対応 |
| §7 ASR | Parakeetと端末内Apple Speech、録音、再認識、同一録音比較。143.1でParakeetの録音・文字起こし画面を確認。160.1でApple Speech選択後の録音・文字起こしを確認。指定英文による3.9秒再録音で両エンジンの結果表示を確認し、画面上でApple Speech WER 0%／0.13秒／178.5 MB、Parakeet WER 57%／0.03秒／179 MBを表示。利用者は「両方一致」は両方から結果が出た意味と訂正した。文字起こし本文を独立に確認していないため、WER値はアプリ表示として記録し、利用者による文字列一致確認とは扱わない。同じ録音をParakeetで再認識した2回目もWER 57%を表示したが、文字列の一致や別録音での再現性を示すものではない。Apple Speech録音3.863秒、単独認識184 ms／186.2 MBも診断で成功。音声ファイルは端末内に保持し、本文は保存・共有しない | Parakeetの誤り原因・別録音での再現性、文字列の反復一致、権限拒否後の再試行、ASR取消・中断回復 |
| §8 RE-USE | 任意設定、固定音声による端末検証gate、5分上限、元音声保持、ASRによる比較を実装。同梱固定音声を機内モードで比較し、RE‑USE処理3.02秒／RTF 0.278／モデルload1.87秒／MLX peak1.01 GB／process RSS peak452.5 MB。さらにiPhone 16／160.1で利用者の3.9秒録音をApple Speechにより比較し、両経路の結果表示を確認。処理1.24秒／RTF 0.321／model load0.14秒／MLX peak1.39 GB、認識時間はなし0.16秒／あり0.13秒。設定をOFFに戻し、元録音は保持 | 各結果のWER差、実聴での明瞭さ・学習上の効果、反復性能・熱挙動 |
| §9 LLM | Gemma 4 E2B教材生成、構造/難易度/日本語存在gate、教材編集、問題メモ、非表示、弱点から新しい用例を生成。160.1でオンライン/機内モード中の教材生成に成功し、オフライン生成直後のプロセス再起動後も保存一覧から復元 | 実機の完全モデル識別、意味品質、異なる条件・熱状態での反復性能 |
| §10 学習画面 | 再生・速度・原文表示切替・復習登録、カテゴリ/難易度/Part検索、フレーズ選択、弱点からの新規用例、教材移動。PR #94で復習項目の削除導線を分離。SimulatorとTestFlight 190.1の実機で削除操作を確認 | VoiceOver、Dynamic Type、片手操作の実機確認 |
| §11 スピーキング | お手本再生、録音、文字起こし比較、単語差分/WERと正規化 | 実機での録音中断・機内モード。厳密な音素/発音採点は初期要件外 |
| §12 復習 | 決定的スケジューラ、履歴、習熟度、教材versionと回答記録。PR #94のSimulator UIテストとTestFlight 190.1の実機で、評価履歴の保持・項目削除時の履歴cascade・再起動後の空状態を確認 | 実機での新たな復習回答・予定更新、通常の利用履歴復元 |
| §13 保存 | SQLite transaction、保護領域、schema migration、教材と回答履歴 | 古いデータからの実機アップグレード・復元 |
| §14 UI | 学習、復習、設定、モデル管理と診断の各画面 | 実機操作性・アクセシビリティ |
| §15 診断 | 固定fieldの端末内ログ、共有用エクスポート、TTS/ASR/RE-USE計測、LLM TTFT/デコードtokens/sec。RSSはプロセス全体の観測値として表示 | 異なる条件・熱状態での反復測定、診断共有確認。RSSをモデル単体メモリと解釈しない |
| §16 安全性 | 学習データと音声は端末内。通常ログに音声/文字起こしを出さず、model binaryや署名情報をGitに含めない | 変更ごとの継続的なdiff/secret review |
| §17 CI/CD | PR #94のquality/core/iOS Simulator UI/unsigned archive/review-gate [run 42818188522](https://github.com/Guch1120/english_app/actions/runs/42818188522)成功。PRを含むmain `973d388`のTestFlight upload [run 42825893942](https://github.com/Guch1120/english_app/actions/runs/42825893942)が成功。190.1はTestFlightで表示され、iPhone 16へ導入済み | 将来の変更buildの配布・インストール |
| §18 実機 | iPhone 16/iOS 26.4.2で160.1のオンライン/オフラインGemma、保存復元・性能表示、Kokoro/Pocket TTS、ASR、RE‑USE、Kokoro repeatを確認。190.1はTestFlight経由で導入・起動。前回試験用の復習項目を削除し、保存済み0件・履歴空を確認、アプリ再起動後も維持。関連のない録音・履歴は保持 | Parakeetの別録音での精度・再現性、RE‑USEのWER差・実聴効果、LLM意味品質、オフライン復習、新しい回答・予定更新、割り込み・長時間・熱挙動 |

## 完了判定

自動CIが通過したコード実装と、物理iPhone上で未確認の受け入れ項目は別である。PR #94はquality、Core、macOS package、iOS Simulator UI、unsigned archive、review-gateが成功してmainへマージ済みで、復習履歴の再起動保持と削除cascadeをSimulatorで確認した。TestFlight run 42825893942で190.1をアップロードし、TestFlight表示とiPhone 16への導入を確認した。PR #94で実装した削除導線は実機でも動作し、既知の試験項目と関連履歴を削除した後の空状態が再起動後も保持された。PR #66をDocker testsとGitHub macOS CI成功後にmainへマージし、TestFlight 160.1をiPhone 16へ導入した。160.1ではオンライン/機内モード中のGemma教材生成と保存復元、機内モード・Wi‑Fi OFF中のKokoro/Pocket TTS生成、固定サンプルによるParakeet/Apple Speech認識とRE‑USE比較を確認した。追加の実機確認ではKokoro repeat再生が2回聞こえ、依頼した英文を録音した利用者所有音声で両ASRの結果表示を確認した。画面上のWER表示はApple Speech 0%、Parakeet 57%。利用者は「両方一致」は両方から結果が出た意味と訂正し、文字起こし本文を独立に確認していないため、文字列一致の利用者確認とは扱わない。同じ録音のParakeet再認識でもWER 57%だったが、別音声での再現性や文字列レベルの一致を確立しない。保存した同じ3.9秒音声でApple SpeechとRE‑USEの比較も行い、両経路の認識時間とRE‑USE処理時間・メモリを観測したが、各WER差を保存しておらず、音の明瞭さも未評価。LLM意味品質、復習・回答履歴の実機復元、バックグラウンド再生、割り込み、反復性能・熱挙動などが残るため、アプリ全体の実機受け入れ完了とは扱わない。試験後、RE‑USE設定OFF、機内モードOFF、Wi‑Fi ON、`suruga-kenkoland`接続を再確認した。
