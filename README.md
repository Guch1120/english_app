# English Trainer

iPhone向けローカル英語学習アプリと、交換可能な音声AI基盤。SwiftUI / iOS 18以降。

Phase 1〜7（共通基盤、TTS、ASR、復習・履歴、端末内Gemma教材生成、RE-USE音声強調、安定化）はmainへマージ済みです。最新のTestFlightアップロードは0.1.0 (121.1)で成功しています。接続中のiPhoneで最後に確認できたインストール版は119.1です。USB読み取り・起動確認はできますが、iOS 26.4.2ではリモートタッチ操作が使えないため、実機の音声・モデル操作は未確認の項目として管理しています。Simulator CIは画面遷移と教材保存後の再起動復元も確認します。

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
- [新規App ID・Secrets登録とiPhone検証手順](Docs/iPhone-Setup.md)

実装状況は [Status](Docs/Status.md) 参照。モデルの端末内準備、オフライン動作、ライセンス、制約は各機能ドキュメントを参照してください。ローカルテストの成功はiOSでの動作確認を意味しません。個人データ・モデル重み・署名ファイルはGitへ登録しないでください。

TestFlight配布は[専用手順](Docs/TestFlight.md)を参照してください。`ios-testflight` EnvironmentへAPIキーを登録すると、mainへのマージ後に自動で配布を開始します。Actionsからの手動実行もできます。USB用Development署名とは別の配布経路です。

PRの自動チェックは[チェック範囲と結果の見方](Docs/Automated-Checks.md)を参照してください。`review-gate`に結果を集約し、ドキュメントだけの変更でも軽量な安全性チェックは実行します。自動承認・自動マージは有効化していません。

音声モデルの構成・ライセンス・検証範囲は[TTS統合](Docs/TTS.md)を参照してください。
ASRモデルの構成・録音データの扱い・実機検証項目は[ASR統合](Docs/ASR.md)を参照してください。
復習予定、習熟度、学習履歴は[復習システム](Docs/Review.md)を参照してください。
モデル検索、オンデバイスLLM、教材の保存・検証は[LLM統合](Docs/LLM.md)を参照してください。
RE-USEのモデル管理、端末確認、比較とライセンスは[音声強調](Docs/REUSE.md)を参照してください。
安定化フェーズの完了条件と機内モード確認は[Phase 7](Docs/Phase7.md)を参照してください。
