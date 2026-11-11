# 初期版の受け入れ確認

仕様書 [Specification-v1.md](Specification-v1.md) §20の18条件を、コード・CIと実機の証拠で確認する。フェーズのコードがマージ済みであることと、実機の受け入れ完了は分けて記録する。

2026-11-11 follow-up：iPhone 16／iOS 26.4.2／TestFlight 0.1.0 (201.1)で設定画面のデータ操作が診断一覧より前にあることを確認。`settings.deleteAllData`を押すと確認alertに「キャンセル」と「削除」が表示された。「キャンセル」を選ぶとalertが閉じ、削除操作は実行されなかった。確認時点のホーム画面は今日の復習0件でサンプル教材が表示されていた。実データ削除は実行していない。WDAのスクリーンショットと要素ログは確認後にrepo外の一時領域ごと削除した。

2026-11-11 follow-up：TestFlight run [42917141650](https://github.com/Guch1120/english_app/actions/runs/42917141650)で0.1.0 (208.1)のmacOS archive、cloud signing、App Store Connect uploadが成功し、dSYM artifactも保持された。TestFlightに208.1が表示された後、利用者の事前許可に基づいてiPhone 16へ更新した。Docker USB queryで208.1を確認し、アプリ起動後も稼働 (PID 4313)、固定fieldのappLaunch診断イベント1件、RSS peak 110,018,560 bytes、thermal nominalを確認した。これは短時間のインストール・起動確認で、全機能や長時間安定性の受け入れではない。

2026-11-11 follow-up：利用者の承認を受け、iPhone 16／iOS 26.4.2／TestFlight 208.1でGemma 4 E2B候補 `gemma-4-E2B-it.litertlm`（Apache-2.0、revision `3d48132a`、2.59 GB）を取得した。開始前の端末空き容量は74.27 GB。画面でダウンロードとSHA-256検証の完了を確認し、「端末で動作確認」の固定プロンプト推論にも成功した。その後、対象の2.59 GB候補のみをモデル管理画面から削除し、既存の2.01 GB GPUモデルが残っていることを確認して選択を戻した。既存のWeb候補も保持されている。学習データ・録音は操作していない。これは新規候補の取得・整合性検証・固定推論・削除の実機証拠であり、教材生成の意味品質、反復性能、熱挙動の確認ではない。WDA runnerは利用者不在中の再起動時パスワード要求を避けるため、稼働したまま維持している。

2026-11-11 follow-up：iPhone 16／iOS 26.4.2／TestFlight 208.1の設定画面をWDAで確認し、「次回起動後も最新の録音を保持」はON（値1）だった。設定は変更せず、録音の再起動後保持や実削除はこの確認では試していない。WDA runnerは稼働中のまま保ち、画面操作で録音・学習データを変更していない。

2026-11-11 follow-up：iPhone 16／iOS 26.4.2／201.1の「オフライン利用の準備」画面で、TTS、ASR、LLM、RE-USEの準備状態がいずれも準備済み／利用可能と表示されることを確認した。画面にはモデルをオンラインで取得・端末確認してから機内モードへ切り替え、アプリ再起動後に教材、TTS、ASR、保存教材、復習履歴を確認する4段階の手順と、LLM／RE-USEは固定確認済みの場合に限って試す旨が表示された。画面確認のみで、この操作中にネットワーク設定やモデル状態を変更せず、オフライン推論も再実行していない。過去の実機オフライン推論証拠は上表のとおり。

2026-11-11 follow-up：PR [#105](https://github.com/Guch1120/english_app/pull/105)で設定画面の「データ」操作を診断履歴より上へ移し、削除確認に明示的なキャンセル操作を追加した。GitHub macOS Validate [run 42888324021](https://github.com/Guch1120/english_app/actions/runs/42888324021)でquality、Docker Core、macOS package、Simulator build/analyze/launch、15件のUI test、unsigned archive、review-gateが成功。UI testは診断一覧の下でもデータ削除導線へ到達できることと、削除確認のキャンセル動作を確認した。実機で実データの全削除は行っていない。PRは`aa9fe44`を含むmainへマージ済み。

2026-11-11 follow-up：TestFlight upload [run 42897334281](https://github.com/Guch1120/english_app/actions/runs/42897334281)が0.1.0 (201.1)をアップロードし、Apple処理後にiPhone 16／iOS 26.4.2のTestFlight画面へ更新が表示された。利用者の事前許可に基づき更新を開始。USB installed-app queryで201.1を確認し、English Trainerを起動後もPID 4258で稼働、起動診断イベント1件、RSS peak 109,838,336 bytes、thermal state nominalを検証した。学習データ・録音は変更していない。これは更新後の起動・診断確認で、長時間安定性や全機能の回帰試験ではない。

2026-11-11 JST follow-up：iPhone 16 / iOS 26.4.2 / TestFlight 190.1で、設定画面のWi‑FiスイッチがOFF（値0）であることを確認してから機内モードをON（値1）にした。この状態でサンプル教材から一時レビュー項目を登録して「普通」と回答した。画面の復習回数は1回、成功1 / 失敗0、習熟度100%、次回予定は2026-11-13 00:24。学習・復習履歴画面に同じ評価と次回日時が表示された。English TrainerプロセスをSIGKILLし、機内モードON・Wi‑Fi OFFのまま再起動した後も、保存済み1件、評価イベント、次回予定が残っていた。確認後、この試験項目だけを削除し、cascade確認を経て保存済み0件、試験用復習イベントなしへ戻した。既存の学習操作履歴は保持された。機内モードOFF、Wi‑Fi ONへ戻し、設定画面のWi‑Fi行に接続中のネットワークが表示されることを確認した。文字起こし本文・録音は取得・変更していない。

2026-11-11 JST follow-up：USBケーブル再接続後、Docker内のWDAからiPhone 16／iOS 26.4.2で`ready: true`を確認した。復習タブの画面を読み取った後、Homeを押してEnglish Trainerを前面へ戻し、学習タブが表示されることを確認した。保存済み復習項目は0件のままで、学習データを変更する操作はしていない。これは短いHome→前面復帰の確認であり、音声のバックグラウンド再生、画面ロック中の再生、音声割り込みは確認していない。Bluetooth経路の確認は利用者の希望で保留し、通常利用時に問題が出れば調査する。WDA runnerを停止し、一時スクリーンショットとログを削除した。

2026-11-11 follow-up：PR [#102](https://github.com/Guch1120/english_app/pull/102)でオフラインレビュー復元の実機確認記録を追加し、`e6877bf`としてmainへマージした。PR workflow [run 42846010844](https://github.com/Guch1120/english_app/actions/runs/42846010844)ではqualityとreview-gateが成功し、docs-only差分に応じてCore/iOSをskipした。加えて同じhead `a18a25741fa9bcb9e5467b28ae3802cfd5465d96`に対して手動で全Validate workflow [run 42845728398](https://github.com/Guch1120/english_app/actions/runs/42845728398)を実行し、quality、Docker Core tests、GitHub macOS package tests、Simulator build/analyze、起動、14件のUI test、unsigned distribution archive、review-gateがすべて成功した。Bluetooth音声経路の試験は利用者の希望により保留し、通常利用で再生に問題が出た場合に調査する。これは試験済みとは扱わない。

2026-11-11 follow-up：Bluetooth試験を利用者の希望により保留する方針と、#102時点のAcceptance記録をPR [#103](https://github.com/Guch1120/english_app/pull/103)に整理し、`d3e0137`としてmainへマージした。PR checks [run 42856332110](https://github.com/Guch1120/english_app/actions/runs/42856332110)のquality/review-gate、および同head `cbbe8ff2eb2d3335faf901b589a296ea5d047947`の全Validate [run 42855477925](https://github.com/Guch1120/english_app/actions/runs/42855477925)でquality、Docker Core、GitHub macOS package/Simulator/UI/unsigned archive、review-gateが成功した。

2026-11-10 follow-up：PR [#94](https://github.com/Guch1120/english_app/pull/94) はiPhone Simulator UIテストで、評価済み苦手項目の履歴がアプリ再起動後も残り、項目削除後に同項目の復習履歴も消えることを確認した。quality、Docker Core tests、macOS package tests、iOS Simulator build/analyze、起動、UIテスト、未署名distribution archive、review-gateは[run 42818188522](https://github.com/Guch1120/english_app/actions/runs/42818188522)で成功し、PRは`973d388`としてマージ済み。これはSimulator上の操作確認であり、iPhone実機での削除確認ではない。2026-11-10の後続WDA接続試行は`Device is not connected`となり、実機操作はできなかった。

2026-11-10 follow-up：PR #94を含むmain commit `973d388`をTestFlight manual upload [run 42825893942](https://github.com/Guch1120/english_app/actions/runs/42825893942)から**0.1.0 (190.1)**としてアップロードした。GitHub upload jobは成功したが、Apple側の処理完了・TestFlight表示・iPhoneへのインストールはまだ確認していない。

2026-11-10 later follow-up：利用者がUSBケーブルを抜き差しした後、Docker内pymobiledevice3からiPhone 16 (`iPhone17,3`)、iOS 26.4.2を再検出し、WDA `ready: true`を確認した。TestFlightに表示されたEnglish learning App **0.1.0 (190.1)**を更新し、USB installed-app queryで190.1を確認。English Trainerはクラッシュせず起動した。復習画面に残っていた前回受け入れ試験用の唯一の苦手項目（復習1回）を対象に、削除確認ダイアログと履歴cascadeの説明を確認して削除した。保存済み苦手項目は0件、復習履歴は空になり、アプリを再起動した後も両方の状態が維持された。これはTestFlight 190.1の実機削除・履歴cascade・再起動保持の確認である。ユーザー録音や別の学習項目は削除していない。録音・文字起こし本文は記録・共有していない。

2026-11-10 JST follow-up：iPhone 16 / iOS 26.4.2 / TestFlight 190.1で、既存のサンプル教材から単語1件を一時登録。復習画面で「今日の復習 1件」と未復習状態を確認し、「普通」で回答した。表示は復習1回、成功1 / 失敗0、習熟度100%、次回2026-11-12 23:24（回答から2日後）。復習履歴画面にも評価と次回日時が記録された。確認後、今回作成した項目だけを削除し、確認画面の履歴cascade表示を経て、保存済み0件・復習履歴なしへ戻った。既存の学習操作履歴は残り、学習画面の英文表示はOFFに戻した。保存録音、既存教材、他の履歴は削除していない。WDA runnerと一時ログ／スクリーンショットは停止・削除済み。

2026-11-10 JST follow-up：iPhone 16 / iOS 26.4.2 / TestFlight 190.1で設定からLLMモデル管理を開き、「Gemma 4を探す」を実行。画面に対応モデルファイル9件が表示され、候補行にファイルサイズ・Apache-2.0・revision、状態に応じたダウンロード/検証・使用・削除操作が表示された。UIには検索語のみがHugging Faceへ送信され教材文・録音は送信しない旨が示された。既存モデルのダウンロード・削除は行わず、検索画面を閉じた。これはモデル検索画面とメタデータ表示の確認で、個々の候補の端末互換性や新規ダウンロード成功の確認ではない。

2026-11-10 follow-up：PR #66の修正を含むTestFlight **0.1.0 (160.1)** をiPhone 16 (`iPhone17,3`)、iOS 26.4.2へ導入した。TestFlight画面とUSB installed-app queryの両方で160.1を確認。154.1で2回失敗したものと同じGemma教材条件で生成し、生成結果の画面表示、保存一覧への追加、アプリプロセス終了後の再起動でも同じ生成日時・Gemma model IDの教材が残ることを確認した。再起動後の別の成功生成で、model-load 1.5秒、最初の応答0.8秒、生成4.8秒、43.1 tokens/sec、process RSS 572.3 MBを性能欄で確認。端末診断には先の成功生成の`LLM · inference · succeeded`とRSS 567.8 MBも記録された。教材本文・プロンプトは記録・共有していない。各値は一回の観測であり、一般的な性能や意味品質を保証しない。TestFlight workflow [run 42758129010](https://github.com/Guch1120/english_app/actions/runs/42758129010) は成功。

2026-11-10 follow-up：後続のオフラインTTS確認のため一時的に機内モードを有効化し、試験後に機内モードをOFF、Wi‑Fiを`suruga-kenkoland`へ再接続した。BluetoothはOFFのまま。比較入力は既定の英文へ復元した。

2026-11-10 JST follow-up：iOS 26.4.2のiPhone 16で、座標指定のWDAタッチにより機内モードON・Wi‑Fi OFFを確認し、160.1を起動した。Gemma 4 E2Bの端末内教材生成は機内モード中に成功し、生成画面に本文が表示された。生成の直後にEnglishTrainerプロセス（PID 3771）をSIGKILLし、機内モードを維持したままアプリを再起動。生成教材画面の「保存済み」一覧を再度開き、GemmaモデルIDの保存行3件を確認した。これは取得済みモデルを用いたオフラインGemma生成とプロセス再起動後の保存復元の証拠で、教材の意味品質は別途評価が必要。試験後は機内モードをOFFに戻し、Wi‑Fiが元の`suruga-kenkoland`へ再接続したことを設定画面で確認した。iOS 26.4.2ではCoreDevice音声ストリームが未対応（iOS 27以降を要求）で、TTS実音声、Pocketとの比較、repeatループ、ASR実音声は今回未確認。再生操作の計測値も確認できていない。録音・教材本文は記録していない。

2026-11-10 JST follow-up：TestFlight 160.1のスピーキング画面でApple Speech（端末内）を選択した状態から録音を開始し、停止後に文字起こしを実行した。録音は開始・保存でき、アプリプロセスは継続していた。無音に近い入力のため文字起こしは失敗し、英語音声の認識品質は確認していない。端末診断にもApple Speechの録音成功と文字起こし失敗が記録された。Apple Speechを選択して録音を開始するとクラッシュするという以前の症状は160.1では再現しなかった。

2026-11-10 JST follow-up：TestFlight 0.1.0 (160.1)のTTS比較画面からKokoroを実行し、端末内診断で15:58の`TTS · inference · succeeded`（125 ms、cache 373 KB）を確認した。アプリコードではこの成功イベントは音声生成またはキャッシュ読込の後、`AVAudioPlayer.play()`が成功してから記録されるため、端末内プレイヤーの起動まで確認できた。比較画面の測定行は画面下にあり、当時の表示範囲には現れていなかった。iOS 26.4.2ではCoreDevice音声ストリームが未対応のため実際に聞こえたかは確認できていない。音質とrepeatループの受け入れは未完了。ユーザー音声や教材本文は記録していない。

同日 follow-up：同じ固定英文でPocket TTSを2回実行し、端末診断に16:04の成功（129 ms）と16:05の成功（117 ms）が記録された。どちらもcache 373 KB、熱状態nominalで、アプリコード上はプレイヤー起動後のイベント。後のオフライン試験ではWDA入力に日本語IME文字が残ったため、純英語入力で再試験した。iPhone 16／160.1で機内モードON・Wi‑Fi OFFを設定し、アクセシビリティ値が英文のみであることを確認した固定英文をKokoroとPocketの両方へ入力。画面上でKokoroの生成1.14秒、音声長3.32秒、24,000 Hz、RTF 0.343、プロセスRSSピーク551.6 MB、Pocketの生成1.48秒、音声長2.48秒、24,000 Hz、RTF 0.599、RSSピーク751.1 MBを確認した。診断にも両方のinference successが記録され、実装では`AVAudioPlayer.play()`成功後に記録する。これはオフライン生成とプレイヤー開始までの証拠で、実際に聞こえた音・音質・主観比較・repeatループは未確認。試験後に機内モードをOFF、Wi‑Fiを元の`suruga-kenkoland`へ復帰し、比較入力を既定値へ戻した。

2026-11-10 JST follow-up：iPhone 16／iOS 26.4.2／TestFlight 160.1で、リポジトリ同梱の固定`sample_noisy.wav`を録音欄へ入れ、機内モードON・Wi‑Fi OFFの状態でParakeet 110MとApple Speech（端末内）の同一録音比較を実行した。両バックエンドの文字起こし結果と計測表示が返り、アプリは継続動作した。Parakeetの初回実行は約5.35秒、初回モデルロード約5.28秒、process RSSピーク392.2 MB。Apple Speechは約0.81秒、process RSSピーク180.9 MB。ParakeetとApple Speechの比較画面に出たWERは、テスト音声と異なる教材文を参照した値なので認識品質の指標として扱わない。続けて同じ固定録音をRE‑USEなし／ありで比較し、RE‑USE処理3.02秒、RTF 0.278、モデル読み込み1.87秒、MLXピークメモリ1.01 GB、認識中のprocess RSS観測ピーク452.5 MBを確認した。これはオフラインで各処理と結果表示が完了した証拠であり、音声強調・認識品質の主観評価ではない。固定サンプルと割り当て録音は確認後にアプリの「録音を削除」で削除し、RE‑USE設定をOFFへ戻した。機内モードをOFF、Wi‑FiをONにして`suruga-kenkoland`へ復帰した。ユーザーの発話を録音していない。以前存在した47.8秒の保存録音は今回の録音操作で置き換わっており、復元できていない。

2026-11-10 JST follow-up：TestFlight 160.1のiPhone 16で、利用者が保存済みの5.1秒の英語録音を使い、機内モード・Wi‑Fi OFFのままParakeetとApple Speechの双方で文字起こしできることを確認したとの報告を受けた。端末内診断の同一比較記録も両方`succeeded`（Parakeet 277 ms／process RSS peak 180.8 MB、Apple Speech 330 ms／172.5 MB）を示す。モデルは比較前にロード済みであり、この時間はwarm inferenceの観測値。本文は取得・記録・共有していない。比較画面のWERは正解文が録音内容と一致する証拠がないため品質評価には使わない。録音は利用者の所有物で、試験後も保持し、削除していない。Apple Speechの初回認識失敗後に再試行が成功した。音声認識成功は確認したが、この記録から発話内容の正確さを独立評価したものではない。

同日、KokoroのrepeatをONにした再生が2回分聞こえたと利用者が確認した。repeatをOFFに戻し、TTSエンジンをKokoroへ復元した。Pocket TTSも利用者から正常動作との報告を受けた。実聴評価は利用者の確認であり、音質・発音の専門評価ではない。今回の録音・認識にはPocket TTSではなく、ASRのParakeetとApple Speechを使用した。

同日 follow-up：利用者がApple Speechで録音できていなかったと報告し、依頼した固定英文を再録音した。新しい3.9秒録音を両エンジンで比較し、利用者は両方の結果が表示されたと確認した。画面上のWERはParakeet 57%（0.03秒、process RSS peak 179 MB）、Apple Speech 0%（0.13秒、178.5 MB）。後の確認で、利用者の「両方一致」は両エンジンとも結果が出たという意味で、両文字起こしが参照文と一致したという意味ではないと明確になった。文字起こし本文を独立に確認していないため、WER表示はアプリ表示値として記録し、利用者による文字列一致確認とは扱わない。Apple Speech単独認識の端末診断は録音成功（3.863秒）、文字起こし成功（184 ms、process RSS peak 186.2 MB）。これらは一回の実測であり、Parakeetの差分原因・反復品質は未確認。録音は端末内に保持し、文字起こし本文は記録・共有していない。新しい録音に置き換わった以前の録音は復元していない。PR #87の前回記述は再録音前の値であり、本記録を最新状態とする。

同日 follow-up：同じ3.9秒の利用者録音を保持したまま、iPhone 16／iOS 26.4.2／TestFlight 160.1の同じ教材画面でApple Speechを選択し、RE‑USEなし／ありの比較を実行した。画面は両方の文字起こし結果を表示し、認識時間はRE‑USEなし0.16秒、あり0.13秒。RE‑USE処理は1.24秒、RTF 0.321、モデル読み込み0.14秒、MLXピークメモリ1.39 GB。WERを各結果ごとに確実に採取できていないため認識精度の差とは扱わない。利用者は実聴なしで記録することを選択したため、音の明瞭さ・学習上の効果は未評価とする。文字起こし本文は記録・共有していない。RE‑USE設定はOFFへ戻し、元録音は端末に保持した。これは実録音で両経路の処理完了と一回の計測を示すが、音声強調の品質・学習上の効果は未確認。

同日 follow-up：上記と同じ保存音声をParakeet 110Mで再認識した。画面のWERは57%で、先の同じ音声による57%と一致した。これは同じ録音に対するWER表示の2回分の観測であり、文字起こし文字列同士の一致や別音声での精度・再現性を示すものではない。再試行の文字起こし本文は取得・記録・共有せず、録音も保持した。

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
| iPhone 16で起動 | TestFlight 190.1をiPhone 16 / iOS 26.4.2へ導入し、USB installed-app query、WDA起動、画面表示を確認。レビュー項目・履歴の削除後も起動する | 長時間安定性、バックグラウンド復帰 |
| 初回取得後オフライン動作 | 160.1を機内モードで起動し、Gemma E2B生成成功を確認。生成直後のSIGKILLと機内モード中の再起動後も保存済みGemma行3件を確認。Wi‑Fi OFF中のKokoro/Pocket純英語生成、利用者録音のParakeet/Apple Speech結果表示、同梱固定音声によるRE‑USE比較も確認。2026-11-11に機内モード中の復習回答・履歴・次回予定のプロセス再起動復元を実機確認。201.1のオフライン準備画面には4機能の準備状態と手動チェックリストが表示された | Gemma生成の意味品質、録音条件を変えた反復認識。今回の表示確認だけではオフライン実推論を証明しない |
| 英文保存と学習 | SQLite tests、Simulator教材保存・再起動テスト。160.1で生成Gemma教材の保存・アプリ再起動後の一覧復元を確認。190.1でサンプル教材を開き、英文を表示して復習項目へ登録・回答。機内モード中のSIGKILL・再起動後もレビュー回答履歴を確認 | アップグレード経由での既存教材・学習データ復元 |
| Kokoro/Pocket切替・生成・比較 | 160.1で両モデルへ同じ純英語固定文を入力し、機内モード・Wi‑Fi OFF中に生成。Kokoro 1.14秒／音声3.32秒／RTF 0.343／RSS 551.6 MB、Pocket 1.48秒／音声2.48秒／RTF 0.599／RSS 751.1 MB。利用者がPocket TTSの動作とKokoroのrepeat再生2回分の聴取を確認 | 音質・発音の専門評価、中断・音声経路変更、長時間安定性 |
| 英文を聞きテキスト表示 | 160.1でKokoro/Pocket音声の生成を確認し、利用者が再生を聴取。190.1ではサンプル教材の英文表示を画面で確認 | 速度・訳表示を含む実機一連操作、音声経路変更 |
| 苦手単語・文章登録 | 保存tests、Simulator復習登録テスト。iPhone 16 / 190.1でサンプル教材の単語を一時登録し、「普通」で回答後に関連履歴とともに削除して0件へ復帰 | 文章全体登録、理由選択の実機確認 |
| マイクをローカルASRで認識 | Parakeet録音・停止後の表示を143.1で確認。160.1でApple Speech選択後の録音・文字起こしを確認。依頼英文の再録音で両エンジンの結果表示を確認し、アプリ画面はApple Speech WER 0%、Parakeet WER 57%を表示。同じ録音のParakeet再認識でもWER 57%を表示。利用者は「両方一致」は両方で結果が出た意味と訂正しており、本文を独立確認していない | 別音声でのParakeet精度・再現性、文字列レベルの再認識比較。マイク権限拒否後の再試行は利用者の希望で試験を見送り、未確認 |
| お手本との文字差分 | alignment unit tests、結果UIを実装 | 録音停止後の結果・評価表示 |
| 苦手項目を繰り返し復習 | scheduling/persistence testsとPR #94のSimulator UIテストで回答履歴・削除cascade・再起動保持を確認。iPhone 16 / 190.1で一時登録した項目に「普通」と回答し、復習1回、成功1 / 失敗0、習熟度100%、次回予定を確認。2026-11-11は機内モードON・Wi‑Fi OFF中に同様の回答を行い、SIGKILL・再起動後も履歴と予定が残ることを確認。試験項目と履歴を削除後、保存済み0件・試験イベントなし・既存の学習操作履歴保持を確認 | 複数評価段階での長期予定推移 |
| Gemma E2Bで英文生成 | 154.1で同条件2回失敗。160.1ではオンライン/オフライン双方で成功し、プロセス再起動後も保存一覧に残ることを確認。2回目の成功生成で1.5秒load、0.8秒TTFT、4.8秒生成、43.1 tokens/sec、572.3 MB process RSSを観測 | 教材品質の意味評価、異なる条件・熱状態での反復性能 |
| モデル検索・取得・削除 | カタログ、SHA-256、再開・削除処理とDocker tests。190.1のiPhone 16でGemma検索から9件の候補とメタデータを表示。208.1では2.59 GB候補を取得してSHA-256検証・固定プロンプト推論に成功し、その候補のみ削除。既存2.01 GB GPUモデルが残り選択を復元 | 別候補の端末互換性、教材生成品質、反復性能・熱挙動 |
| RE-USE ON/OFF | 任意比較・固定音声確認gateを実装。143.1で設定OFFと保存済み端末確認状態を確認。160.1では同梱固定音声によるオフライン比較（3.02秒、RTF 0.278、モデル読込1.87秒、MLXピーク1.01 GB、process RSS観測ピーク452.5 MB）に加え、利用者の3.9秒実録音をApple Speechで比較し、両経路の結果表示を確認。実録音のRE‑USE処理1.24秒、RTF 0.321、モデル読込0.14秒、MLXピーク1.39 GB、認識時間はなし0.16秒／あり0.13秒。試験後に設定をOFFへ戻し録音を保持 | 実録音でのWER差、実聴での明瞭さ・学習上の効果、反復性能・熱挙動 |
| モデル時間・メモリ確認 | 160.1 Gemma成功生成で1.5秒model-load、0.8秒TTFT、4.8秒生成、43.1 tokens/sec、572.3 MB RSSを画面で確認。別の成功イベントは診断RSS 567.8 MB | 反復・熱状態比較。RSSはアプリ全体の値として解釈 |
| 学習履歴の再起動保持 | SQLiteとSimulator再起動テスト。190.1で回答・次回予定・履歴が記録され、機内モードON・Wi‑Fi OFF中のSIGKILL・再起動後も維持された。試験用項目・履歴だけを削除し、保存済み0件、試験イベントなし、既存の学習操作履歴保持を確認 | 過去バージョンから更新した実機データの復元 |
| エラー後の安定性 | cancellation/coordinator/integrity tests。キャンセル済みleaseをbusy競合より先に判定する回帰testを追加。SpeakingTrainingModelは実行中ASR backendにもcancelを転送。PR #110 Validate run 42907001478でquality、Docker Core、macOS package、Simulator build/analyze/launch/UI、unsigned archive、review gateが成功 | iPhoneのASR中断・復帰。Parakeet TDTのネイティブ推論は即時停止APIがなく、SDK呼び出し終了後に結果を破棄してアンロードする |
| GitHub Actionsビルド | PR #105のfull Validate [run 42888324021](https://github.com/Guch1120/english_app/actions/runs/42888324021)でquality/core/macOS package/Simulator UI 15件/unsigned archive/review-gate成功。PR #110のValidate [run 42907001478](https://github.com/Guch1120/english_app/actions/runs/42907001478)でDocker Core、macOS package、Simulator build/analyze/launch/UI、unsigned archive、quality、review-gateすべて成功。TestFlight upload [run 42897334281](https://github.com/Guch1120/english_app/actions/runs/42897334281)で201.1をアップロード
| 実機インストール | TestFlight 154.1、160.1、190.1をiPhone 16へ導入。さらに201.1をTestFlight画面から更新し、USB installed-app query・アプリ起動・appLaunch診断イベント1件を確認 | 将来の変更buildの再導入 |
| 学習データ・音声の意図しない送信なし | オンデバイス構成、固定診断fields、ログ・外部送信のコードレビュー | 機内モード動作と、外部送信を追加する変更時の再レビュー |

## 最新ビルドで実行する順序

1. 新しいTestFlight buildが利用可能になったら更新し、設定のバージョンと取得済みモデル名を記録する。更新自体でアプリを削除しない限り、同じモデルrevisionの取得済みファイルを再取得する設計ではない。
2. 設定 → ASRモデル管理でParakeetの検証済み表示を確認する。
3. 教材を開き、上部のリスニング／スピーキングを往復する。録音して停止し、認識結果と単語誤り率が手動スクロールなしで表示されるか確認する。これは文字の一致度で、発音採点ではない。
4. KokoroとPocketで同じ英文を再生し、速度・停止・キャッシュ再生を確認する。
5. Apple Speechでモデルを選択後に録音を開始する。権限拒否後の再試行は利用者の希望で見送り、未確認として扱う。Apple Speechとニューラル音声のrepeat toggle、停止、画面ロック時の動作を確認する。LLM管理画面では実測値が返る場合だけdecode tokens/secが表示されることを確認する。
6. RE-USEの固定音声確認と同じ録音の比較、Gemmaの固定プロンプト確認と教材生成を行う。
7. 機内モードへ切り替え、アプリ再起動後に3〜6と復習・履歴復元を確認する。

結果はbuild番号・モデル名・操作・成否・表示された計測値で追記する。録音音声、文字起こしの私的内容、秘密情報をドキュメントやログへ含めない。
