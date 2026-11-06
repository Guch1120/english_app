# English Trainer

iPhone向けローカル英語学習アプリと、交換可能な音声AI基盤。SwiftUI / iOS 18以降。

Phase 1の初期実装です。英文追加、Apple TTS再生、英文・訳の表示切替、苦手単語/文章のSQLite保存、間隔反復、手入力文字起こしの単語比較を実装しています。Kokoro・Pocket TTS・ASR録音・Gemma・RE-USE・モデル検索/ダウンロードは未実装です。

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

実装状況は [Status](Docs/Status.md) 参照。ローカルテストの成功はiOSでの動作確認を意味しません。個人データ・モデル重み・署名ファイルはGitへ登録しないでください。

TestFlight配布は[専用手順](Docs/TestFlight.md)を参照してください。`ios-testflight` EnvironmentへAPIキーを登録し、mainから手動で実行する方式です。USB用Development署名とは別の配布経路です。

PRの自動チェックは[チェック範囲と結果の見方](Docs/Automated-Checks.md)を参照してください。`review-gate`に結果を集約し、ドキュメントだけの変更でも軽量な安全性チェックは実行します。自動承認・自動マージは有効化していません。
