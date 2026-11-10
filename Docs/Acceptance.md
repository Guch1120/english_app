# 初期版の受け入れ確認

仕様書 [Specification-v1.md](Specification-v1.md) §20の18条件を、コード・CIと実機の証拠で確認する。フェーズのコードがマージ済みであることと、実機の受け入れ完了は分けて記録する。

2026-11-08のUSB確認：iPhone 16 (`iPhone17,3`)、iOS 26.4.2、English Trainer build **141.2** がインストール済み。過去の起動観察は [Status.md](Status.md) に記録。利用者はKokoro、Pocket TTS、Parakeet、RE-USEの取得完了を報告し、続いて2026-11-09にGemmaの取得と端末動作確認の成功を報告した。その後、Gemma教材を生成し、学習一覧から開けたことも利用者が確認した。他モデルの実機確認は別途記録する。

2026-11-09：利用者が143.1でリスニング／スピーキング切替と、Parakeetの録音停止後の評価・文字起こし結果表示を確認。USBでもインストール版143.1を確認した。これは通常操作の成功報告であり、機内モードや中断時の検証とは別。

2026-11-10：利用者から151.1へのTestFlight更新完了報告あり。続いてUSBで接続中のiPhone 16 (`iPhone17,3`)、iOS 26.4.2を読み取り確認し、English Trainer **151.1** がインストール済みと確認した。最新アップロード154.1はこの端末にまだ入っていない。Apple Speechの録音開始時クラッシュ修正、PR #60のrepeat再生・LLM throughputは実機で未確認。

2026-11-10追記：PR #60由来のTestFlight build **154.1** はGitHub upload成功後も、USB verifierの追加10分間の確認でiPhone上のinstalled buildが151.1から変化しなかった。TestFlight画面にも154.1が表示されることを確認できておらず、Apple処理・tester割り当て・配布状態は依然不明。WDA再起動は`Timed out while enabling automation mode`でHTTP server起動前に終了した。端末の **Settings → Developer → Enable UI Automation** がOFF、または端末上の確認/パスコード待ちの可能性が残る。必要な利用者操作は、この設定を確認してONにし、端末をunlockしたままにすること。154.1がTestFlightに表示された場合は、先に端末で更新し、USBでinstalled versionを確認してから受け入れ試験を続ける。

同日追記：TestFlightでの更新待ちとは別に、USBの`pymobiledevice3`経由で現在の151.1を起動した。設定画面の端末キャプチャに**0.1.0 (151.1)**が表示され、起動直後のPID 3632が次のUSB process query時にも稼働中で、installed buildも151.1と確認できた。これは151.1での起動・設定表示の証拠であり、154.1や個々の音声/推論機能の確認ではない。

2026-11-10 12:17 JST以降：利用者がUI Automationを有効化し、端末をunlockした状態で154.1へ手動更新した。USBのinstalled-app queryとWDA設定画面の表示で**0.1.0 (154.1)**を確認。WDAの`ready: true`、設定から教材詳細へ移動する操作も成功した。Apple Speechを選択して録音開始・停止を実行し、開始時クラッシュは再現しなかった。固定field診断には録音開始・成功、モデルload成功、無音入力のtranscription失敗が残った。録音・文字起こしの私的データは記録・共有していない。Kokoro-82Mでは教材音声の推論が2回successとして記録された。repeat switchの値をONにできず、ループ再生の実機確認は未完了。

同じ154.1でGemma教材生成を同一条件で2回試し、どちらも`ContentError`で失敗、保存されなかった。固定field診断ではmodel load成功、生成失敗が確認でき、生成内容は記録していない。原因となるモデル出力の具体的内容は診断されていない。修正PRで失敗出力を端末内の修正promptに含め、最大3回まで生成を試み、失敗時の実測値も表示する。修正版の実機生成とdecode tokens/secは新buildで確認する。

2026-11-09 08:43〜08:46 JST：利用者がUI Automationを有効化した後、Docker内WDAのstatus ready、スクリーンショット取得、設定タブへの遠隔tapを確認。画面に**0.1.0 (143.1)**、Kokoro選択中、Parakeetのモデルファイル検証済みを確認した。RE-USE画面はモデル54.2 MB・コンパイルcache 2.6 MB・「この端末で推論を確認済み」、比較設定はOFF。これは既存の端末確認結果の保存状態であり、新しいRE-USE推論をこの操作中に実行した証拠ではない。

同じ実機のLLM管理画面で、`gemma-4-E2B-it-litert-lm · gemma-4-E2B-it-gpu.litertlm`、約2.01 GB、Apache-2.0、revision表示`3d48132a`が「使用中」「端末確認済み」であることを確認。revisionは画面に出た短縮値であり、完全hashや内部candidate IDの取得はまだ行っていない。WDA/画面ファイルはrepo外のprivate作業領域に保存し、学習文・録音・画面をGitへ含めない。

08:47 JSTにWDAから教材生成ボタンを押し、新しい生成教材と保存一覧、生成日時08:47を画面で確認した。内部model IDの表示は`gemma-4-e2b-it-litert-lm-gemma-4-e2b-it-gpu`。これはネットワーク接続中の実機生成であり、機内モードの証拠ではない。生成内容に指定難易度との不一致・英語の解説があった。この結果を受け、生成条件と日本語の存在gateを追加しDockerで検証済み。ただし意味上の難易度適合や翻訳品質を保証する仕組みではなく、修正後のGemma出力は実機で未確認。

2026-11-10：利用者から、TestFlightの **151.1** への更新が完了したとの報告あり。151.1でのApple Speechクラッシュ修正確認はまだ報告されていない。PR #60のマージ後、TestFlight workflow [run 42740151555](https://github.com/Guch1120/english_app/actions/runs/42740151555) が **0.1.0 (154.1)** を正常にアップロードした。154.1のApple処理・配布・インストールは未確認。

| 仕様の条件 | 現在の証拠 | 残る実機確認 |
|---|---|---|
| iPhone 16で起動 | USB起動後のPID継続と設定画面の0.1.0 (154.1)表示を確認 | 154.1で長時間安定性を確認 |
| 初回取得後オフライン動作 | モデル保存・オフライン認識制約・準備画面を実装 | 機内モード＋再起動後の学習と推論 |
| 英文保存と学習 | SQLite tests、Simulator教材保存・再起動テスト | 実機で保存した教材を再表示 |
| Kokoro/Pocket切替・生成・比較 | バックエンド、検証ダウンロード、比較UIを実装。154.1のKokoro inference successを診断で確認 | 両モデルの実聴品質・再生、同一英文比較 |
| 英文を聞きテキスト表示 | Simulatorの速度・訳表示テスト | 音声と表示の実機確認 |
| 苦手単語・文章登録 | 保存tests、Simulator復習登録テスト | 実機で登録 |
| マイクをローカルASRで認識 | Parakeet録音・停止後の表示を143.1で確認。154.1でApple Speechのモデル選択後に録音開始・停止し、クラッシュは再現せず | 実音声の認識結果と権限拒否後の再試行 |
| お手本との文字差分 | alignment unit tests、結果UIを実装 | 録音停止後の結果・評価表示 |
| 苦手項目を繰り返し復習 | scheduling/persistence tests、Simulator復習テスト | 実機で復習と予定更新 |
| Gemma E2Bで英文生成 | 以前の生成成功報告あり。154.1では同じ条件の2試行がContentErrorで失敗し未保存 | 修正retryのTestFlight導入後に生成成功、教材品質、計測値、再起動復元を確認 |
| モデル検索・取得・削除 | カタログ、SHA-256、再開・削除処理とtests | 対応画面から操作、削除後の無効化 |
| RE-USE ON/OFF | 任意比較・固定音声確認gateを実装。143.1の実機で保存された推論確認済み表示とOFF状態を確認 | 新規の固定音声処理の観察と同一録音比較 |
| モデル時間・メモリ確認 | 各バックエンドの計測表示を実装。154.1 Gemma生成失敗で固定fieldの処理時間を確認 | 修正版でmodel-load/TTFT/tokens-sec/RSS表示を確認し実測値を記録 |
| 学習履歴の再起動保持 | SQLiteとSimulator再起動テスト | 実機で再起動復元 |
| エラー後の安定性 | cancellation/coordinator/integrity tests、対話UI | 通信中断、推論取消、バックグラウンド復帰 |
| GitHub Actionsビルド | PR #60の必須check [run 42734887369](https://github.com/Guch1120/english_app/actions/runs/42734887369) 成功。TestFlight upload [run 42740151555](https://github.com/Guch1120/english_app/actions/runs/42740151555) で154.1をアップロード | 実機確認は別途必要 |
| 実機インストール | USBで141.2/143.1と151.1の導入を確認。利用者から151.1へのTestFlight更新完了報告あり。154.1のupload成功 | 154.1のApple処理・内部配布・導入を確認 |
| 学習データ・音声の意図しない送信なし | オンデバイス構成、固定診断fields、ログ・外部送信のコードレビュー | 機内モード動作と、外部送信を追加する変更時の再レビュー |

## 最新ビルドで実行する順序

1. TestFlightで154.1が利用可能になったら更新し、設定のバージョンと取得済みモデル名を記録する。更新自体でアプリを削除しない限り、同じモデルrevisionの取得済みファイルを再取得する設計ではない。
2. 設定 → ASRモデル管理でParakeetの検証済み表示を確認する。
3. 教材を開き、上部のリスニング／スピーキングを往復する。録音して停止し、認識結果と単語誤り率が手動スクロールなしで表示されるか確認する。これは文字の一致度で、発音採点ではない。
4. KokoroとPocketで同じ英文を再生し、速度・停止・キャッシュ再生を確認する。
5. Apple Speechでモデルを選択後に録音を開始し、権限許可・拒否後の再試行を確認する。Apple Speechとニューラル音声のrepeat toggle、停止、画面ロック時の動作を確認する。LLM管理画面では実測値が返る場合だけdecode tokens/secが表示されることを確認する。
6. RE-USEの固定音声確認と同じ録音の比較、Gemmaの固定プロンプト確認と教材生成を行う。
7. 機内モードへ切り替え、アプリ再起動後に3〜6と復習・履歴復元を確認する。

結果はbuild番号・モデル名・操作・成否・表示された計測値で追記する。録音音声、文字起こしの私的内容、秘密情報をドキュメントやログへ含めない。
