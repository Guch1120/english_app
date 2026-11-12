# 引き継ぎ（2026-11-12 追記）：リスニング／スピーキングの「次の文へ」

[Handoff-2026-11-12.md](Handoff-2026-11-12.md) の続き。このセッションは Sonnet 5.5 が担当し、別モデルへ引き継ぐ。
元チェックアウト `/home/robo25/yamaguchi/english_app` の古い `Docs/Handoff-2026-11-09-current.md`（Apple Speechクラッシュ等）は未追跡ファイルのまま触っていない。その内容のうち #52–#56 等の旧PRは現状未確認。

## ユーザーの要望

ホームのリスニング教材が1文ごとに別画面で、文を変えるたびにホームへ戻るのが面倒。リスニングとスピーキングは同じ文で揃える必要はない（どちらもお手本再生がある）。各タブに「次の文へ」ボタンを付けてほしい。

## 実装（ブランチ `codex/practice-next-sentence`、worktree `english_app-gui`）

変更は `Apps/EnglishTrainer/EnglishTrainerApp.swift` のみ。

- `LessonView` がリスニング用 `listeningID` とスピーキング用 `speakingID` を別々に持つ。初期値はホームで開いた教材。タブを切り替えても互いの文は変わらない。
- 「次の文へ」（`goNext`）：表示中の教材の並び（非表示を除く `visibleItems`）で次へ進み、末尾から先頭へ戻る。教材が1件だけなら表示しない。押すと再生を停止する。リスニングでは英文・日本語訳の表示をリセット。
- リスニング：従来の「次の教材」は新しい画面を積む `NavigationLink`（戻る操作が増える）だったのを、その場で切り替えるボタン（id `lesson.listeningNext`）に置換。
- スピーキング：文字起こし結果の下に同じボタン（id `lesson.speakingNext`）。録音中・処理中は無効。録音は教材IDに紐づくので、別の文へ移ると既存の「保存録音をこの教材と比較」の案内が出る（録音は消えない）。
- ホームのフッター文言を更新。

## 検証状況

- Swift（iOS）はLinux/Dockerでビルドできないため、**この変更のコンパイル・UIは未確認**。型・構文は目視レビューのみ。Docker の `Scripts/test.sh` / `quality.sh` はパッケージ側の確認で、iOS成功の証拠ではない。iOSの確認は GitHub Actions（Validate）に任せる。
- UIテストは追加していない（既存テストは「次の教材」を参照していない）。必要なら `lesson.listeningNext` / `lesson.speakingNext` を使うテストを追加する。
- 実機で未確認：ボタンの位置・押しやすさ、スピーキングで文を移ったときの録音／結果表示の整合、次の文への移動中の再生停止。

## 次にやること

1. PR の Validate 4チェックを確認し、通ればマージ（`testflight` ラベルを付けると実機確認用ビルドが出る）。
2. TestFlight ビルドで、リスニング・スピーキング各タブの「次の文へ」を実機確認し、結果を UI-Design.md / Status.md に反映。
3. [Handoff-2026-11-12.md](Handoff-2026-11-12.md) の「次にやること」（スピーキング結果カードの実機確認など）は未着手のまま残る。
