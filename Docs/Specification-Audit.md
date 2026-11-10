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
| Apple Speech 録音開始時クラッシュ | PR #57でauthorization callbackをMainActor隔離の外に移動。145.1で報告されたクラッシュを対象とした | 利用者が151.1へ更新済みと報告。次の154.1以降で権限許可・拒否後の再試行とモデル選択後の録音開始を確認 |
| §6.3 全TTSの繰り返し再生 | PR #60でApple synthesizerの完了delegateによるrepeat loopを追加。ニューラル音声を含め全engineにtoggleを適用 | TestFlight 154.1以降でApple/ニューラル双方の繰り返し・停止・画面ロックを確認 |
| §15.1 LLM decode tokens/sec | PR #60でLiteRT-LM 0.19.1の`Conversation.getBenchmarkInfo()`を用い、実測デコード速度が返る場合のみ表示。実験APIを明示opt-in | 160.1でload 1.5秒、TTFT 0.8秒、生成4.8秒、43.1 tokens/sec、process RSS 572.3 MBを一回観測。反復性能・熱比較は未確認 |

## 仕様本文の照合

| 仕様 | 実装・証拠 | 残る確認 |
|---|---|---|
| §5 共通AI操作・モデル情報 | 共通サービスprotocol、モデル情報、検証付きダウンロード、排他実行、cancel/unload。Model-Information.md参照 | 実機のロード状態・失敗回復 |
| §6 TTS | Kokoro、Pocket TTS、Apple音声、話者選択、再生制御、全engine repeat、速度、キャッシュ、比較、生成時間/RTF/RSS/音声長/サンプルレート、主観メモを実装。160.1でrepeat switchをOFFからONへ切替可能なことを座標タッチで確認（プロセス再起動後はOFFに戻る） | ループ再生そのもの、iPhoneでの実聴品質、話者データ、長時間安定性。iOS 26.4.2ではCoreDevice音声ストリームは非対応 |
| §7 ASR | Parakeetと端末内Apple Speech、録音、再認識、同一録音比較 | 実機での認識品質、遅延、中断回復 |
| §8 RE-USE | 任意設定、固定音声による端末検証gate、5分上限、元音声保持、ASRによる比較を実装 | 固定音声の実機推論・品質・時間・メモリ |
| §9 LLM | Gemma 4 E2B教材生成、構造/難易度/日本語存在gate、教材編集、問題メモ、非表示、弱点から新しい用例を生成。160.1でオンライン/機内モード中の教材生成に成功し、オフライン生成直後のプロセス再起動後も保存一覧から復元 | 実機の完全モデル識別、意味品質、異なる条件・熱状態での反復性能 |
| §10 学習画面 | 再生・速度・原文表示切替・復習登録、カテゴリ/難易度/Part検索、フレーズ選択、弱点からの新規用例、教材移動 | VoiceOver、Dynamic Type、片手操作の実機確認 |
| §11 スピーキング | お手本再生、録音、文字起こし比較、単語差分/WERと正規化 | 実機での録音中断・機内モード。厳密な音素/発音採点は初期要件外 |
| §12 復習 | 決定的スケジューラ、履歴、習熟度、教材versionと回答記録 | 実機アップグレード時の復元 |
| §13 保存 | SQLite transaction、保護領域、schema migration、教材と回答履歴 | 古いデータからの実機アップグレード・復元 |
| §14 UI | 学習、復習、設定、モデル管理と診断の各画面 | 実機操作性・アクセシビリティ |
| §15 診断 | 固定fieldの端末内ログ、共有用エクスポート、TTS/ASR/RE-USE計測、LLM TTFT/デコードtokens/sec。RSSはプロセス全体の観測値として表示 | 異なる条件・熱状態での反復測定、診断共有確認。RSSをモデル単体メモリと解釈しない |
| §16 安全性 | 学習データと音声は端末内。通常ログに音声/文字起こしを出さず、model binaryや署名情報をGitに含めない | 変更ごとの継続的なdiff/secret review |
| §17 CI/CD | PR #66のquality/core/iOS/review-gate [run 42752311642](https://github.com/Guch1120/english_app/actions/runs/42752311642)とTestFlight upload [run 42758129010](https://github.com/Guch1120/english_app/actions/runs/42758129010)が成功。160.1を実機に導入 | Apple処理・配布可否は後続buildで継続確認 |
| §18 実機 | iPhone 16/iOS 26.4.2で160.1の起動、オンライン/機内モード中のGemma生成成功、オフラインでのプロセス再起動・保存復元とLLM性能表示を確認。Apple Speechの録音開始/停止、Kokoro inference successは154.1で確認。repeat switchのON操作を確認。Acceptance.md参照 | TTS実音声とループ再生、ASR実音声、LLM意味品質、オフラインTTS/ASR/復習、割り込み・長時間・熱挙動 |

## 完了判定

自動CIが通過したコード実装と、物理iPhone上で未確認の受け入れ項目は別である。PR #66をDocker testsとGitHub macOS CI成功後にmainへマージし、TestFlight 160.1をiPhone 16へ導入した。160.1ではオンライン/機内モード中のGemma教材生成に成功し、オフラインでのプロセス再起動後も保存済みGemma教材を復元した。再起動後の成功生成でmodel-load/TTFT/decode throughputとprocess RSSを一度観測した。TTS実音声・repeat loop、ASR実音声、教材意味品質、オフラインTTS/ASR/復習、バックグラウンド再生、割り込み、反復性能・熱挙動などが残るため、アプリ全体の実機受け入れ完了とは扱わない。
