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
| §15.1 LLM decode tokens/sec | PR #60でLiteRT-LM 0.19.1の`Conversation.getBenchmarkInfo()`を用い、実測デコード速度が返る場合のみ表示。実験APIを明示opt-in | macOS CIでAPI compile/UIを確認済み。TestFlight 154.1以降の実機で値と生成動作を確認。値が返らない場合は非表示 |

## 仕様本文の照合

| 仕様 | 実装・証拠 | 残る確認 |
|---|---|---|
| §5 共通AI操作・モデル情報 | 共通サービスprotocol、モデル情報、検証付きダウンロード、排他実行、cancel/unload。Model-Information.md参照 | 実機のロード状態・失敗回復 |
| §6 TTS | Kokoro、Pocket TTS、Apple音声、話者選択、再生制御、全engine repeat、速度、キャッシュ、比較、生成時間/RTF/RSS/音声長/サンプルレート、主観メモを実装 | PR CIとiPhoneでのrepeat、話者データ、再生品質、長時間安定性 |
| §7 ASR | Parakeetと端末内Apple Speech、録音、再認識、同一録音比較 | 実機での認識品質、遅延、中断回復 |
| §8 RE-USE | 任意設定、固定音声による端末検証gate、5分上限、元音声保持、ASRによる比較を実装 | 固定音声の実機推論・品質・時間・メモリ |
| §9 LLM | Gemma 4 E2B教材生成、構造/難易度/日本語存在gate、教材編集、問題メモ、非表示、弱点から新しい用例を生成 | 実機の完全モデル識別、オフライン生成、意味品質と再起動復元 |
| §10 学習画面 | 再生・速度・原文表示切替・復習登録、カテゴリ/難易度/Part検索、フレーズ選択、弱点からの新規用例、教材移動 | VoiceOver、Dynamic Type、片手操作の実機確認 |
| §11 スピーキング | お手本再生、録音、文字起こし比較、単語差分/WERと正規化 | 実機での録音中断・機内モード。厳密な音素/発音採点は初期要件外 |
| §12 復習 | 決定的スケジューラ、履歴、習熟度、教材versionと回答記録 | 実機アップグレード時の復元 |
| §13 保存 | SQLite transaction、保護領域、schema migration、教材と回答履歴 | 古いデータからの実機アップグレード・復元 |
| §14 UI | 学習、復習、設定、モデル管理と診断の各画面 | 実機操作性・アクセシビリティ |
| §15 診断 | 固定fieldの端末内ログ、共有用エクスポート、TTS/ASR/RE-USE計測、LLM TTFT/デコードtokens/sec。RSSはプロセス全体の観測値として表示 | 実機での値・画面・共有確認。RSSをモデル単体メモリと解釈しない |
| §16 安全性 | 学習データと音声は端末内。通常ログに音声/文字起こしを出さず、model binaryや署名情報をGitに含めない | 変更ごとの継続的なdiff/secret review |
| §17 CI/CD | PR #60のrequired checks [run 42734887369](https://github.com/Guch1120/english_app/actions/runs/42734887369)と、TestFlight upload [run 42740151555](https://github.com/Guch1120/english_app/actions/runs/42740151555)が成功 | Apple処理・配布可否はupload成功だけでは確認できない |
| §18 実機 | iPhone 16/iOS 26.4.2で154.1の起動・設定表示、Apple Speechの録音開始/停止、Kokoro inference successを確認。Acceptance.md参照 | repeat switch操作と音声ループ、LLM生成と実測throughput、オフライン・品質・再起動・割り込み・熱/メモリの確認 |

## 完了判定

自動CIが通過したコード実装と、物理iPhone上で未確認の受け入れ項目は別である。PR #60までの実装PRはmainにマージ済みで、TestFlight 154.1も手動更新によりiPhone 16へ導入された。154.1ではApple Speechの録音開始/停止は成功し、Kokoro inferenceも成功したが、Gemma教材生成は同一条件の2試行ともContentErrorで失敗・未保存だった。修正版の再試行・失敗時メトリクスはこのPRで実装中であり、Docker/macOS CI成功と新TestFlightでの実機再確認が必要。繰り返し再生・LLM速度、オフライン動作、モデル推論品質、バックグラウンド再生と安定性も未完了であり、アプリ全体の実機受け入れ完了とは扱わない。
