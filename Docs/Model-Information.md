# 共通モデル情報と実行状態

## 仕様§5.2への対応

設定の「AIモデル情報・状態」で、アプリが扱える各モデルの情報を共通表示する。LLMは保存した対応カタログ候補を表示する。任意の検索結果を実行可能にする変更ではない。モデルの取得・削除・端末確認は従来の専用管理画面で行う。

| 要件 | データ/表示元 |
|---|---|
| ID・名・開発元・種別 | 拡張したModelDescriptor。原開発元不明のLLMは配布元と未確認表示を区別 |
| 対応言語・ランタイム・必要OS | アプリで有効にした言語、固定SDK版、アプリ対象OS。全端末で実行できる保証とは別 |
| モデルversion・取得元 | immutable manifestの完全revisionと固定版model URL。LLMも選択したファイルのrevisionを表示 |
| ファイルサイズ・SHA-256 | manifestの全ファイル、合計bytesと各ファイルのhash。追加Kokoro話者も別manifestを開ける |
| ライセンス・機能 | 専用管理画面と同じライセンス情報、現在アプリで有効にした機能 |
| 取得済み状態 | 各controllerが検証したインストール状態。取得完了を推論成功とみなさない |
| ロード済み状態 | adapterのSDK load成功/unload完了を共有coordinatorへ通知。busyから推測しない |
| 動作検証結果 | TTSは同revisionの非cache生成記録、Parakeetは新しく記録するrevision別認識成功flag、RE-USE/LLMは既存の端末確認gate |

AppleのOS音声はアプリがモデルファイルやhash・SDKロード状態を取得できないため、「OS管理・取得不可」と明示する。モデル情報が欠けた旧ModelDescriptor JSONはnil/空配列/未確認で復元し、値を捏造しない。

## 実行状態の意味

ModelRuntimeCoordinatorはleaseの対象IDとSDK load成功を別々に追跡する。失敗したleaseが終わっても、SDKのunload確認がない限りロード済み記録を勝手に消さない。通常のapp経路は従来どおり成功・エラーの両方でunloadを行う。キャンセルを処理失敗として記録せず、次の成功でそのモデルの直近失敗を消す。

ロード済みは「adapterのloadが成功し、unloadされていない」状態で、重みの物理RAM常駐やモデル単体メモリを意味しない。特にRE-USE SDKは最初の強調時に遅延準備する部分がある。メモリ計測は既存のプロセスRSS表示を利用する。

状態は端末内メモリだけに保持し、モデルIDと固定の失敗分類を扱う。プロンプト・学習文・録音・文字起こし・任意のError.descriptionを新しい状態へ保存しない。画面表示中のみ1秒間隔でsnapshotを取得し、画面を閉じるとTaskを終了する。

Parakeetの過去の文字起こしからエンジンを推測して確認済みにしない。この変更以降に同revisionで認識が成功したときだけ確認flagを記録する。従来の推論可否gateを新たに緩めない。

RE-USE manifestは既存の同じModelCatalog/ModelSourceからSDK非依存で読む関数を抽出し、実際の取得と情報表示の両方で使う。既存モデルのrevision・bytes/hash・保存場所は変更しない。新規SDK依存やモデル重みを追加しない。

## 検証状況

Docker41 tests成功。旧descriptor互換とmetadata往復、RE-USE catalogの固定版/サイズ、lease失敗後のloaded状態、unload・回復、キャンセルとエラーの区別を検証した。quality成功、Swift構文parse成功。当時は新画面のSimulator UIとiOSビルドが未検証だった。その後の macOS CI [run 42734887369](https://github.com/Guch1120/english_app/actions/runs/42734887369) でiOS Simulator build/analyze、アプリ起動、Simulator UI suite、unsigned distribution archiveが成功し、native adapterの型検査を含むiOSビルド経路を確認した。iPhone 16上でのモデル情報表示や実モデル状態の一致は引き続き実機確認が必要。

この機能は後続の統合PRでmainへマージ済み。過去の作業場所とブランチ情報は当時の履歴であり、現在の作業状態を表さない。
