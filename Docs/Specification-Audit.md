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
| §6 TTS | Kokoro、Pocket TTS、Apple音声、話者選択、再生制御、全engine repeat、速度、キャッシュ、比較、生成時間/RTF/RSS/音声長/サンプルレート、主観メモを実装。160.1でrepeat switchをOFFからONへ切替可能なことを座標タッチで確認（プロセス再起動後はOFFに戻る）。同ビルドのTTS比較画面からKokoro（15:58、125 ms）とPocket（16:04、129 ms／16:05、117 ms）を実行し、端末診断に`TTS · inference · succeeded`を確認（cache 373 KB、熱状態 nominal）。機内モード・Wi‑Fi OFF中に純英語の固定文で再試験し、Kokoro生成1.14秒／音声3.32秒／24,000 Hz／RTF 0.343／process RSS 551.6 MB、Pocket生成1.48秒／音声2.48秒／24,000 Hz／RTF 0.599／RSS 751.1 MBを比較画面で確認。両方の診断successも取得し、実装上は`AVAudioPlayer.play()`の成功後に記録される。実聴音質とrepeat loopは未確認 | ループ再生そのもの、iPhoneでの実聴品質、話者データ、長時間安定性。iOS 26.4.2ではCoreDevice音声ストリームは非対応 |
| §7 ASR | Parakeetと端末内Apple Speech、録音、再認識、同一録音比較。143.1でParakeetの録音・文字起こし画面を確認。160.1でApple Speech選択後に録音を開始・保存し、アプリ継続を確認。2026-11-10に同梱固定`sample_noisy.wav`を機内モード・Wi‑Fi OFF中にParakeet 110MとApple Speechで認識し、双方の結果表示を確認（Parakeet初回約5.35秒／model load約5.28秒／process RSS peak392.2 MB、Apple Speech約0.81秒／RSS peak180.9 MB） | 実際の英語発話とマイク入力での品質、遅延、中断回復、権限拒否後の再試行。比較画面WERは音声と異なる教材参照に対する値のため品質評価に使わない |
| §8 RE-USE | 任意設定、固定音声による端末検証gate、5分上限、元音声保持、ASRによる比較を実装。2026-11-10に同じ同梱固定音声を機内モード中に比較し、RE‑USE処理3.02秒／RTF 0.278／モデルload1.87秒／MLX peak1.01 GB／process RSS peak452.5 MBを確認。テスト音声はアプリから削除し、設定OFFと機内モードOFF・Wi‑Fi接続を確認 | 実際の英語発話での品質・実用効果、異なる条件での反復性能 |
| §9 LLM | Gemma 4 E2B教材生成、構造/難易度/日本語存在gate、教材編集、問題メモ、非表示、弱点から新しい用例を生成。160.1でオンライン/機内モード中の教材生成に成功し、オフライン生成直後のプロセス再起動後も保存一覧から復元 | 実機の完全モデル識別、意味品質、異なる条件・熱状態での反復性能 |
| §10 学習画面 | 再生・速度・原文表示切替・復習登録、カテゴリ/難易度/Part検索、フレーズ選択、弱点からの新規用例、教材移動 | VoiceOver、Dynamic Type、片手操作の実機確認 |
| §11 スピーキング | お手本再生、録音、文字起こし比較、単語差分/WERと正規化 | 実機での録音中断・機内モード。厳密な音素/発音採点は初期要件外 |
| §12 復習 | 決定的スケジューラ、履歴、習熟度、教材versionと回答記録 | 実機アップグレード時の復元 |
| §13 保存 | SQLite transaction、保護領域、schema migration、教材と回答履歴 | 古いデータからの実機アップグレード・復元 |
| §14 UI | 学習、復習、設定、モデル管理と診断の各画面 | 実機操作性・アクセシビリティ |
| §15 診断 | 固定fieldの端末内ログ、共有用エクスポート、TTS/ASR/RE-USE計測、LLM TTFT/デコードtokens/sec。RSSはプロセス全体の観測値として表示 | 異なる条件・熱状態での反復測定、診断共有確認。RSSをモデル単体メモリと解釈しない |
| §16 安全性 | 学習データと音声は端末内。通常ログに音声/文字起こしを出さず、model binaryや署名情報をGitに含めない | 変更ごとの継続的なdiff/secret review |
| §17 CI/CD | PR #66のquality/core/iOS/review-gate [run 42752311642](https://github.com/Guch1120/english_app/actions/runs/42752311642)とTestFlight upload [run 42758129010](https://github.com/Guch1120/english_app/actions/runs/42758129010)が成功。0.1.0 (160.1)はApple処理後、iPhone 16へTestFlightで導入済み | 160.1より後のTestFlight buildは未作成・未配布 |
| §18 実機 | iPhone 16/iOS 26.4.2で160.1の起動、オンライン/機内モード中のGemma生成成功、オフラインでのプロセス再起動・保存復元とLLM性能表示を確認。機内モード・Wi‑Fi OFF中の純英語固定文でKokoro/Pocket TTS生成と測定、同梱固定音声でParakeet/Apple Speechのオフライン認識結果表示とRE‑USEあり／なし比較を確認。テスト音声の削除、設定OFF、機内モードOFF、Wi‑Fi復帰も確認。160.1でApple Speech選択後の録音開始・停止とアプリ継続を確認。repeat switchのON操作を確認。Acceptance.md参照 | TTSの実聴音声とループ再生、実際の発話に対するASR/RE‑USE品質、LLM意味品質、オフライン復習、割り込み・長時間・熱挙動 |

## 完了判定

自動CIが通過したコード実装と、物理iPhone上で未確認の受け入れ項目は別である。PR #66をDocker testsとGitHub macOS CI成功後にmainへマージし、TestFlight 160.1をiPhone 16へ導入した。160.1ではオンライン/機内モード中のGemma教材生成に成功し、オフラインでのプロセス再起動後も保存済みGemma教材を復元した。機内モード・Wi‑Fi OFF中の純英語固定文でKokoro/Pocket TTS生成と比較測定、同梱固定音声でのオフラインParakeet/Apple Speech認識とRE‑USE比較も確認した。再起動後のGemma成功生成でmodel-load/TTFT/decode throughputとprocess RSSを一度観測した。TTS実聴・repeat loop、実際の英語マイク入力によるASR品質、教材意味品質、復習・回答履歴の実機復元、バックグラウンド再生、割り込み、反復性能・熱挙動などが残るため、アプリ全体の実機受け入れ完了とは扱わない。
