# 新規アプリの署名・実機確認

USBの信頼認証だけではIPAは起動できません。署名に含まれるApp ID・証明書・端末UDIDが必要です。この手順はApple Developer Programのチームを使う開発用配布です。無料Personal Team方式はこのCIでは対応していません。既存アプリのSecretsはコピーしません。

1. [Apple Developer](https://developer.apple.com/account/resources/identifiers/list) で新規Explicit App ID `jp.guch1120.EnglishTrainer` を登録。別IDにする場合はXcode projectとScripts/build-device.sh内のIDも合わせて変更。
2. DevicesでiPhoneのUDIDを登録。PCが信頼済みでもDeveloper Portalへの登録は別途必要。UDIDは公開Issueやチャットへ貼らない。
3. CertificatesでApple Development証明書を用意し、秘密鍵を含むパスワード付きPKCS#12 (`.p12`) を用意する。既存の秘密鍵を所有していない証明書だけでは署名不可。Macがない場合はDocker内のOpenSSLで鍵/CSRを生成→PortalにCSRを登録→証明書をダウンロード→同じ秘密鍵と証明書をp12にまとめられる。鍵・CSR用の保存先はリポジトリ外の暗号化/アクセス制限された場所にする。鍵やp12をGitに入れない。
4. Profilesで **iOS App Development** を作成。新App ID・対応するApple Development証明書・当該iPhoneを選び、`.mobileprovision` を取得。[Apple公式手順](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)参照。
5. [リポジトリ設定](https://github.com/Guch1120/english_app/settings/environments) → Environments → `ios-development` を作成。Deployment branchesをmainに制限し、可能なら承認者を設定。下表をEnvironment secretsへ登録。Repository secretsで広く共有する必要はない。

| Secret | 値 |
|---|---|
| IOS_CERTIFICATE_BASE64 | p12のbase64（1行） |
| IOS_CERTIFICATE_PASSWORD | p12を作成したパスワード |
| IOS_PROFILE_BASE64 | mobileprovisionのbase64（1行） |
| APPLE_TEAM_ID | DeveloperのMembership detailsのTeam ID |
| DEV_IPA_PASSWORD | IPA成果物の暗号化用の十分長い新しいパスワード |

base64は暗号化ではありません。エンコード結果もチャット・Git・ログへ貼らず、GitHubのSecret入力欄に直接設定してください。App Store Connect API keyはこの手動プロファイル方式では不要です。期限切れ・端末追加時はプロファイルとSecretsを更新します。

6. PRをレビューしてmainへマージ。Settings→Rules→Rulesetsでmainへの直接pushを禁止し、PRレビュー・Validateのcore/iosを必須化（リポジトリ設定への適用はまだ行っていません）。Actions→Device build→Run workflow→main。署名は手動実行のみです。
7. 成功後、暗号化artifactを取得し、リポジトリ外の非公開ディレクトリで復号する。入力を画面表示しない `read -rs DEV_IPA_PASSWORD; export DEV_IPA_PASSWORD` の後、OpenSSLで `openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in EnglishTrainer.ipa.enc -out EnglishTrainer.ipa -pass env:DEV_IPA_PASSWORD`。作業後 `unset DEV_IPA_PASSWORD`。OpenSSLや端末操作ツールもDocker内で実行すること。
8. iPhoneの設定→プライバシーとセキュリティ→デベロッパモードをONにし再起動。既存の信頼済みUSB接続を維持する。
9. Docker内で復号・USBインストールする（既存usbmuxdを利用。ホストへのパッケージ追加やサービス再起動はしない）。

```bash
bash Scripts/download-ipa.sh RUN_ID /path/to/private-signing-directory
bash Scripts/iphone.sh check
bash Scripts/iphone.sh install /path/to/private-signing-directory/builds/RUN_ID/EnglishTrainer.ipa
bash Scripts/iphone.sh installed
# オプション：iOS 17.4+の実機スクリーンショット
bash Scripts/capture-iphone.sh /path/to/private-signing-directory
```

`download-ipa.sh`は指定ディレクトリ内の`dev-ipa-password.txt`を読み、成果物を同じ場所の`builds/RUN_ID`へ保存する。`iphone.sh`はUSB端末1台を自動選択し、複数台では`IPHONE_UDID`で明示する。ソケット変更は`USBMUXD_SOCKET_PATH`で指定する。スクリーンショットもリポジトリ外へ保存する。DeveloperDiskImageの初回準備にはダウンロードとAppleへのデバイス用パーソナライズ要求が発生する。

開発用CLIはideviceinstaller 1.1.1（GPL-2.0）/libimobiledevice 1.3.0（LGPL-2.1）、オプションのpymobiledevice3 11.50.0（GPL-3.0）。アプリへリンク・同梱せずDocker内の開発ツールとして使う。

この手順はDevelopment署名IPAのUSB直接配布。TestFlightは別途App Store Connectのアプリレコード、配布用署名、アップロード用認証とCIが必要。


## 実機確認チェック

- OSバージョン、空き容量、機内モードでApple英語音声の再生可否を記録。
- 英文を追加→音声再生→英文/訳表示→単語と文章を復習登録。
- 復習の4評価で期日更新。強制終了→再起動後も教材・予定が残る。
- Kokoro/Pocket TTSの音声を準備し、同じ英文で再生・聴き比べ・キャッシュ削除。
- Parakeetモデル取得、マイク許可、録音/停止/再生/削除/再起動後復元と再認識。
- Apple Speechは端末内認識に対応する端末だけで許可・認識を確認。
- Parakeet/Apple Speechの文字起こし差分と復習登録。
- LLMモデル検索・取得・固定プロンプト確認・教材生成・アプリ再起動後のオフライン教材生成。
- RE-USE取得・端末固定音声確認・同一録音の処理前後比較・再生・モデル/キャッシュ削除。
- すべてのモデルを取得して端末確認後、機内モードでアプリ再起動、TTS/ASR/生成教材/復習を確認。
- 着信などの音声割り込み、イヤホン切断、ホーム移動、メモリ警告時の停止・復帰。
- データ削除の確認ダイアログと再起動後の空状態。
- VoiceOver、文字サイズ、ダークモード、TestFlight更新を確認。

LinuxのDockerテスト、GitHub macOSのiOSビルド、iPhone上のCore ML/MLX実行は別の確認です。CI成功だけでは実機動作済みとは扱いません。未実施項目は機種、iOS、モデルrevision、結果、処理時間、RSS観測値、発熱を記録します。

## USB UI自動操作（WDA）

Apple Developerの画面操作を避けるためのAPI手順と、端末登録に使う証明書・iPhoneだけに範囲を絞る設定は[WDA自動操作の手順](WDA-Automation.md)を参照してください。登録後、署名済みrunnerのビルドとiPhoneへのインストールは別工程です。まだWDA runnerが入るまでは、スクリーンショット取得・起動確認はできますが、タップ操作はできません。

## Macなしで新しい証明書用CSRを作る例

以下はユーザーが署名登録を行う段階で実行します。先に `bash Scripts/test.sh` でDockerイメージを作っておきます。保存先はリポジトリの外です。

```bash
mkdir -p -m 700 "$HOME/.config/english-trainer-signing"
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$HOME/.config/english-trainer-signing:/signing" english-trainer-dev \
  openssl req -new -newkey rsa:2048 \
  -keyout /signing/development.key -out /signing/development.csr \
  -subj '/CN=English Trainer Development'
```

表示される秘密鍵パスワードを設定・保管します。PortalのApple Development証明書作成画面へ `development.csr` だけをアップロードし、取得した証明書を同じフォルダーの `development.cer` として保存します。

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$HOME/.config/english-trainer-signing:/signing" english-trainer-dev \
  openssl x509 -inform DER -in /signing/development.cer -out /signing/development.pem
docker run --rm -it --user "$(id -u):$(id -g)" \
  -v "$HOME/.config/english-trainer-signing:/signing" english-trainer-dev \
  openssl pkcs12 -export -inkey /signing/development.key -in /signing/development.pem \
  -out /signing/development.p12 -name 'English Trainer Development'
```

後者で秘密鍵のパスワードと、出力p12のパスワードを入力します。**p12のパスワード**を `IOS_CERTIFICATE_PASSWORD` に設定します。証明書チェーンに関する署名エラーが出た場合は対応するApple WWDR中間証明書の確認が必要です。証明書生成・署名そのものは本実装時点で未実行です。
