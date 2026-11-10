# 初期版の受け入れ確認

仕様書 [Specification-v1.md](Specification-v1.md) §20の18条件を、コード・CIと実機の証拠で確認する。フェーズのコードがマージ済みであることと、実機の受け入れ完了は分けて記録する。

2026-11-10 follow-up：PR #66の修正を含むTestFlight **0.1.0 (160.1)** をiPhone 16 (`iPhone17,3`)、iOS 26.4.2へ導入した。TestFlight画面とUSB installed-app queryの両方で160.1を確認。154.1で2回失敗したものと同じGemma教材条件で生成し、生成結果の画面表示、保存一覧への追加、アプリプロセス終了後の再起動でも同じ生成日時・Gemma model IDの教材が残ることを確認した。再起動後の別の成功生成で、model-load 1.5秒、最初の応答0.8秒、生成4.8秒、43.1 tokens/sec、process RSS 572.3 MBを性能欄で確認。端末診断には先の成功生成の`LLM · inference · succeeded`とRSS 567.8 MBも記録された。教材本文・プロンプトは記録・共有していない。各値は一回の観測であり、一般的な性能や意味品質を保証しない。TestFlight workflow [run 42758129010](https://github.com/Guch1120/english_app/actions/runs/42758129010) は成功。

2026-11-10 follow-up：後続のオフラインTTS確認のため一時的に機内モードを有効化し、試験後に機内モードをOFF、Wi‑Fiを`suruga-kenkoland`へ再接続した。BluetoothはOFFのまま。比較入力は既定の英文へ復元した。

2026-11-10 JST follow-up：iOS 26.4.2のiPhone 16で、座標指定のWDAタッチにより機内モードON・Wi‑Fi OFFを確認し、160.1を起動した。Gemma 4 E2Bの端末内教材生成は機内モード中に成功し、生成画面に本文が表示された。生成の直後にEnglishTrainerプロセス（PID 3771）をSIGKILLし、機内モードを維持したままアプリを再起動。生成教材画面の「保存済み」一覧を再度開き、GemmaモデルIDの保存行3件を確認した。これは取得済みモデルを用いたオフラインGemma生成とプロセス再起動後の保存復元の証拠で、教材の意味品質は別途評価が必要。試験後は機内モードをOFFに戻し、Wi‑Fiが元の`suruga-kenkoland`へ再接続したことを設定画面で確認した。iOS 26.4.2ではCoreDevice音声ストリームが未対応（iOS 27以降を要求）で、TTS実音声、Pocketとの比較、repeatループ、ASR実音声は今回未確認。再生操作の計測値も確認できていない。録音・教材本文は記録していない。

2026-11-10 JST follow-up：TestFlight 160.1のスピーキング画面でApple Speech（端末内）を選択した状態から録音を開始し、停止後に文字起こしを実行した。録音は開始・保存でき、アプリプロセスは継続していた。無音に近い入力のため文字起こしは失敗し、英語音声の認識品質は確認していない。端末診断にもApple Speechの録音成功と文字起こし失敗が記録された。Apple Speechを選択して録音を開始するとクラッシュするという以前の症状は160.1では再現しなかった。

2026-11-10 JST follow-up：TestFlight 0.1.0 (160.1)のTTS比較画面からKokoroを実行し、端末内診断で15:58の`TTS · inference · succeeded`（125 ms、cache 373 KB）を確認した。アプリコードではこの成功イベントは音声生成またはキャッシュ読込の後、`AVAudioPlayer.play()`が成功してから記録されるため、端末内プレイヤーの起動まで確認できた。比較画面の測定行は画面下にあり、当時の表示範囲には現れていなかった。iOS 26.4.2ではCoreDevice音声ストリームが未対応のため実際に聞こえたかは確認できていない。音質とrepeatループの受け入れは未完了。ユーザー音声や教材本文は記録していない。

同日 follow-up：同じ固定英文でPocket TTSを2回実行し、端末診断に16:04の成功（129 ms）と16:05の成功（117 ms）が記録された。どちらもcache 373 KB、熱状態nominalで、アプリコード上はプレイヤー起動後のイベント。後のオフライン試験ではWDA入力に日本語IME文字が残ったため、純英語入力で再試験した。iPhone 16／160.1で機内モードON・Wi‑Fi OFFを設定し、アクセシビリティ値が英文のみであることを確認した固定英文をKokoroとPocketの両方へ入力。画面上でKokoroの生成1.14秒、音声長3.32秒、24,000 Hz、RTF 0.343、プロセスRSSピーク551.6 MB、Pocketの生成1.48秒、音声長2.48秒、24,000 Hz、RTF 0.599、RSSピーク751.1 MBを確認した。診断にも両方のinference successが記録され、実装では`AVAudioPlayer.play()`成功後に記録する。これはオフライン生成とプレイヤー開始までの証拠で、実際に聞こえた音・音質・主観比較・repeatループは未確認。試験後に機内モードをOFF、Wi‑Fiを元の`suruga-kenkoland`へ復帰し、比較入力を既定値へ戻した。

2026-11-10 JST follow-up：iPhone 16／iOS 26.4.2／TestFlight 160.1で、リポジトリ同梱の固定`sample_noisy.wav`を録音欄へ入れ、機内モードON・Wi‑Fi OFFの状態でParakeet 110MとApple Speech（端末内）の同一録音比較を実行した。両バックエンドの文字起こし結果と計測表示が返り、アプリは継続動作した。Parakeetの初回実行は約5.35秒、初回モデルロード約5.28秒、process RSSピーク392.2 MB。Apple Speechは約0.81秒、process RSSピーク180.9 MB。ParakeetとApple Speechの比較画面に出たWERは、テスト音声と異なる教材文を参照した値なので認識品質の指標として扱わない。続けて同じ固定録音をRE‑USEなし／ありで比較し、RE‑USE処理3.02秒、RTF 0.278、モデル読み込み1.87秒、MLXピークメモリ1.01 GB、認識中のprocess RSS観測ピーク452.5 MBを確認した。これはオフラインで各処理と結果表示が完了した証拠であり、音声強調・認識品質の主観評価ではない。固定サンプルと割り当て録音は確認後にアプリの「録音を削除」で削除し、RE‑USE設定をOFFへ戻した。機内モードをOFF、Wi‑FiをONにして`suruga-kenkoland`へ復帰した。ユーザーの発話を録音していない。以前存在した47.8秒の保存録音は今回の録音操作で置き換わっており、復元できていない。

2026-11-10 JST follow-up：TestFlight 160.1のiPhone 16で、利用者が保存済みの5.1秒の英語録音を使い、機内モード・Wi‑Fi OFFのままParakeetとApple Speechの双方で文字起こしできることを確認したとの報告を受けた。端末内診断の同一比較記録も両方`succeeded`（Parakeet 277 ms／process RSS peak 180.8 MB、Apple Speech 330 ms／172.5 MB）を示す。モデルは比較前にロード済みであり、この時間はwarm inferenceの観測値。本文は取得・記録・共有していない。比較画面のWERは正解文が録音内容と一致する証拠がないため品質評価には使わない。録音は利用者の所有物で、試験後も保持し、削除していない。Apple Speechの初回認識失敗後に再試行が成功した。音声認識成功は確認したが、この記録から発話内容の正確さを独立評価したものではない。

同日、KokoroのrepeatをONにした再生が2回分聞こえたと利用者が確認した。repeatをOFFに戻し、TTSエンジンをKokoroへ復元した。Pocket TTSも利用者から正常動作との報告を受けた。実聴評価は利用者の確認であり、音質・発音の専門評価ではない。今回の録音・認識にはPocket TTSではなく、ASRのParakeetとApple Speechを使用した。

同日 follow-up：利用者がApple Speechで録音できていなかったと報告し、依頼した固定英文を再録音した。新しい3.9秒録音を両エンジンで比較。参照文は依頼した英文と一致し、画面には両エンジンの結果が表示された。画面上のWERはParakeet 57%（0.03秒、process RSS peak 179 MB）、Apple Speech 0%（0.13秒、178.5 MB）。文字列本文を出力せずに行った一致確認でもApple Speechは参照と一致し、Parakeetは一致しなかった。WER計算は表示値と一致する。Apple Speech単独認識の端末診断は録音成功（3.863秒）、文字起こし成功（184 ms、process RSS peak 186.2 MB）。これらは一回の実測であり、Parakeetの差分原因・反復品質は未確認。録音は端末内に保持し、文字起こし本文は記録・共有していない。新しい録音に置き換わった以前の録音は復元していない。PR #87の前回記述は再録音前の値であり、本記録を最新状態とする。

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
| iPhone 16で起動 | USB/WDAで0.1.0 (160.1)を確認。アプリ終了・再起動後も起動し、保存教材を復元 | 長時間安定性、バックグラウンド復帰 |
| 初回取得後オフライン動作 | 160.1を機内モードで起動し、Gemma E2B生成成功を確認。生成直後のSIGKILLと機内モード中の再起動後も保存済みGemma行3件を確認。Wi‑Fi OFF中のKokoro/Pocket純英語生成、利用者録音のParakeet/Apple Speech結果表示、同梱固定音声によるRE‑USE比較も確認 | 復習・回答履歴の実機確認、Gemma生成の意味品質、録音条件を変えた反復認識 |
| 英文保存と学習 | SQLite tests、Simulator教材保存・再起動テスト。160.1で生成Gemma教材の保存・アプリ再起動後の一覧復元も確認 | 通常教材の実機回答履歴・復習への反映 |
| Kokoro/Pocket切替・生成・比較 | 160.1で両モデルへ同じ純英語固定文を入力し、機内モード・Wi‑Fi OFF中に生成。Kokoro 1.14秒／音声3.32秒／RTF 0.343／RSS 551.6 MB、Pocket 1.48秒／音声2.48秒／RTF 0.599／RSS 751.1 MB。利用者がPocket TTSの動作とKokoroのrepeat再生2回分の聴取を確認 | 音質・発音の専門評価、中断・音声経路変更、長時間安定性 |
| 英文を聞きテキスト表示 | Simulatorの速度・訳表示テスト | 音声と表示の実機確認 |
| 苦手単語・文章登録 | 保存tests、Simulator復習登録テスト | 実機で登録 |
| マイクをローカルASRで認識 | Parakeet録音・停止後の表示を143.1で確認。160.1でApple Speech選択後の録音・文字起こしを確認。依頼英文を再録音した比較で、参照一致を確認。Apple Speech WER 0%、Parakeet WER 57%、両方の結果表示を確認 | Parakeetの誤り原因・反復品質、権限拒否後の再試行 |
| お手本との文字差分 | alignment unit tests、結果UIを実装 | 録音停止後の結果・評価表示 |
| 苦手項目を繰り返し復習 | scheduling/persistence tests、Simulator復習テスト | 実機で復習と予定更新 |
| Gemma E2Bで英文生成 | 154.1で同条件2回失敗。160.1ではオンライン/オフライン双方で成功し、プロセス再起動後も保存一覧に残ることを確認。2回目の成功生成で1.5秒load、0.8秒TTFT、4.8秒生成、43.1 tokens/sec、572.3 MB process RSSを観測 | 教材品質の意味評価、異なる条件・熱状態での反復性能 |
| モデル検索・取得・削除 | カタログ、SHA-256、再開・削除処理とtests | 対応画面から操作、削除後の無効化 |
| RE-USE ON/OFF | 任意比較・固定音声確認gateを実装。143.1の実機で保存された推論確認済み表示とOFF状態を確認。2026-11-10に同梱固定音声で機内モード中のRE‑USEなし／あり同一録音比較を完了し、処理3.02秒、RTF 0.278、モデル読込1.87秒、MLXピーク1.01 GB、process RSSピーク452.5 MBを観測。テスト音声はアプリから削除し、設定をOFFへ戻した | 実際の英語発話での品質・実用効果、異なる条件での反復性能 |
| モデル時間・メモリ確認 | 160.1 Gemma成功生成で1.5秒model-load、0.8秒TTFT、4.8秒生成、43.1 tokens/sec、572.3 MB RSSを画面で確認。別の成功イベントは診断RSS 567.8 MB | 反復・熱状態比較。RSSはアプリ全体の値として解釈 |
| 学習履歴の再起動保持 | SQLiteとSimulator再起動テスト | 実機で再起動復元 |
| エラー後の安定性 | cancellation/coordinator/integrity tests、対話UI | 通信中断、推論取消、バックグラウンド復帰 |
| GitHub Actionsビルド | PR #66のquality/core/iOS/review-gate [run 42752311642](https://github.com/Guch1120/english_app/actions/runs/42752311642)成功。TestFlight upload [run 42758129010](https://github.com/Guch1120/english_app/actions/runs/42758129010)で160.1をアップロード | アップロード成功とApple処理は別確認 |
| 実機インストール | TestFlight 154.1と160.1をiPhone 16へ導入。160.1はTestFlight画面とUSB queryで確認 | 次buildが必要な変更後の反復導入 |
| 学習データ・音声の意図しない送信なし | オンデバイス構成、固定診断fields、ログ・外部送信のコードレビュー | 機内モード動作と、外部送信を追加する変更時の再レビュー |

## 最新ビルドで実行する順序

1. 新しいTestFlight buildが利用可能になったら更新し、設定のバージョンと取得済みモデル名を記録する。更新自体でアプリを削除しない限り、同じモデルrevisionの取得済みファイルを再取得する設計ではない。
2. 設定 → ASRモデル管理でParakeetの検証済み表示を確認する。
3. 教材を開き、上部のリスニング／スピーキングを往復する。録音して停止し、認識結果と単語誤り率が手動スクロールなしで表示されるか確認する。これは文字の一致度で、発音採点ではない。
4. KokoroとPocketで同じ英文を再生し、速度・停止・キャッシュ再生を確認する。
5. Apple Speechでモデルを選択後に録音を開始し、権限許可・拒否後の再試行を確認する。Apple Speechとニューラル音声のrepeat toggle、停止、画面ロック時の動作を確認する。LLM管理画面では実測値が返る場合だけdecode tokens/secが表示されることを確認する。
6. RE-USEの固定音声確認と同じ録音の比較、Gemmaの固定プロンプト確認と教材生成を行う。
7. 機内モードへ切り替え、アプリ再起動後に3〜6と復習・履歴復元を確認する。

結果はbuild番号・モデル名・操作・成否・表示された計測値で追記する。録音音声、文字起こしの私的内容、秘密情報をドキュメントやログへ含めない。
