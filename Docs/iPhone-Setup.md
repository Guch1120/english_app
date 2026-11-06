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
9. Docker内のpymobiledevice3またはlibimobiledeviceのIPAインストール機能を使う。既存PCのusbmuxdを利用する場合はソケットを明示的にマウントし、ホストへ新規パッケージを入れない。USBツール用イメージとバージョン固定・実機インストールは未実装のため、最初の署名ビルド時に端末接続方式を確認して追加する。ホストのusbmuxd再起動・設定変更は行わない。

## 実機確認チェック

- OSバージョン、空き容量、機内モードでApple英語音声の再生可否を記録。
- 英文を追加→音声再生→英文/訳表示→単語と文章を復習登録。
- 復習の4評価で期日更新。強制終了→再起動後も教材・予定が残る。
- 手入力比較で欠落/置換/追加を確認（録音・ASRは未実装）。
- データ削除の確認ダイアログと再起動後の空状態。
- VoiceOver、文字サイズ、ダークモード、音声割り込み、ロック画面再生を確認。

LinuxでのSwiftテストとiOSビルド/実機確認は別です。CI成功とiPhoneでの確認が済むまでは実機動作済みとは扱いません。
