# English Trainer

iPhone向けローカル英語学習アプリと、交換可能な音声AI基盤。SwiftUI / iOS 18以降。

Phase 1〜7の実装とCI対応はmainへマージ済みです。仕様にある初回モデル取得後のオフライン動作、音声品質、実機推論などの物理iPhone確認は継続中です。2026-11-09時点のTestFlight最新アップロードは **0.1.0 (143.1)**、接続中のiPhoneで最後に確認したインストール版は **0.1.0 (141.2)** です。143.1では教材上部のリスニング／スピーキング切替と、録音後の自動文字起こし・結果表示を改善しました。USB接続・ペアリング、Developer Mode、Developer imageを確認し、WDAからアクセシビリティツリーを読めましたが、セッション作成とタップ操作はまだ動作していません。未検証項目と根拠は[実装状況](Docs/Status.md)に記録しています。Simulator CIは画面遷移と教材保存後の再起動復元も確認します。

## Dockerで検証

```bash
bash Scripts/test.sh
# 任意のテストだけ実行
bash Scripts/test.sh --filter CoreTests/testReviewSchedule
```

ホストへのSwift・Pythonパッケージのインストールは不要。ビルドキャッシュは作業ツリー内 `.build`、ツールチェーンはDocker内です。初回はDockerイメージの取得が必要です。

iOSは `.github/workflows/validate.yml` のmacOSランナーで署名なしSimulatorビルド・解析を行います。公開リポジトリにPRを作成してCIを実行してください。実機配布はmain専用の手動 `Device build` で、保護EnvironmentのSecrets登録後に暗号化IPAを生成します。

- [仕様書](Docs/Specification-v1.md)
- [調査・互換性とライセンスの確認状況](Docs/Phase0.md)
- [構成と実装上の制約](Docs/Architecture.md)
- [初期版の受け入れ確認と実機チェック](Docs/Acceptance.md)
- [仕様本文の照合と未完了項目](Docs/Specification-Audit.md)
- [教材の回答・修正・管理](Docs/Lesson-Management.md)
- [直近の作業引き継ぎ](Docs/Handoff-2026-11-08.md)
- [新規App ID・Secrets登録とiPhone検証手順](Docs/iPhone-Setup.md)

実装状況は [Status](Docs/Status.md) 参照。モデルの端末内準備、オフライン動作、ライセンス、制約は各機能ドキュメントを参照してください。ローカルテストの成功はiOSでの動作確認を意味しません。個人データ・モデル重み・署名ファイルはGitへ登録しないでください。

TestFlight配布は[専用手順](Docs/TestFlight.md)を参照してください。配布するPRに `testflight` ラベルを付けてmainへマージするとアップロードを開始します。ラベルなしのマージでは配布しません。Actionsからの手動実行もできます。USB用Development署名とは別の配布経路です。

PRの自動チェックは[チェック範囲と結果の見方](Docs/Automated-Checks.md)を参照してください。`review-gate`に結果を集約し、ドキュメントだけの変更でも軽量な安全性チェックは実行します。自動承認・自動マージは有効化していません。

音声モデルの構成・ライセンス・検証範囲は[TTS統合](Docs/TTS.md)を参照してください。
ASRモデルの構成・録音データの扱い・実機検証項目は[ASR統合](Docs/ASR.md)を参照してください。
復習予定、習熟度、学習履歴は[復習システム](Docs/Review.md)を参照してください。
モデル検索、オンデバイスLLM、教材の保存・検証は[LLM統合](Docs/LLM.md)を参照してください。
RE-USEのモデル管理、端末確認、比較とライセンスは[音声強調](Docs/REUSE.md)を参照してください。
安定化フェーズの完了条件と機内モード確認は[Phase 7](Docs/Phase7.md)を参照してください。
