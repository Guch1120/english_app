# TTS話者選択と比較メモ

## 実装範囲

音声エンジンとは別に話者を選択し、通常学習・復習・比較画面へ同じ選択を適用する。Kokoroは既存のHeartと、追加取得するBella / Michael（米国英語）。Pocket TTSはライセンス確認済みのAlbaのみを表示する。未取得話者は選択欄へ出さず、設定の音声モデル管理から取得する。話者選択はエンジンごとに端末内へ保存し、削除・未準備の場合は標準話者に戻す。

追加話者は基本モデルとは別manifest・別保存ディレクトリ。既存48ファイルのmanifestは変更せず、再取得を要求しない。追加話者の削除で基本モデルや他話者を削除しない。話者IDをキャッシュキーと測定結果へ記録するので、別話者の音声を取り違えない。

聴き比べ結果ごとに2000文字までの主観メモを追加・修正・消去する。計測値とともに保護された端末内ファイルへatomic保存する。旧測定履歴にはメモがなくても復元可能。測定履歴は従来どおり最新100件までで、全学習データ削除ではメモも削除する。診断ログ・外部通信へメモを追加しない。

## 固定版APIとライセンス確認

FluidAudioの変更しないvendor snapshotの`KokoroAneVoicePack.load(fromJSON:)`と`binaryData`を利用する。固定版のJSONをSHA-256検証した後、推論lease内のload時にfp32 packへ変換し、SDKの既存ANE voice pathへatomic保存する。SDKの自動ダウンロードへ委ねない。元データが削除された場合、変換済みpackだけでは新規生成を許可しない。

配布元は基本モデルと同じ[固定revision](https://huggingface.co/FluidInference/kokoro-82m-coreml/tree/2568276a60ff6e7f312afce3dc9e3f07521cb48d)。固定版READMEのlicenseはApache-2.0、元モデルはhexgrad/Kokoro-82M。既存のhexgrad / FluidInference表示を継続する。Docker内で固定URLの実データを取得しサイズとSHA-256を照合した（取得内容はGitへ含めない）。

| path | bytes | SHA-256 |
|---|---:|---|
| voices/af_bella.json | 2678538 | e7bdbe207b927d1e59556dcda69b976cbbdc87be5e4affeea5bf030fca80e55c |
| voices/am_michael.json | 2667552 | ec6e03f1fc30c11020ade45f587a64e1b8c51c08e8ab6f59bdf089f410c2b924 |

## 検証状況

Docker testsは34件成功。追加テストは旧JSON互換・メモ保存復元/長さ上限/消去、固定版追加manifestの分離と話者別キャッシュidentityを確認する。qualityは成功。Swift syntax parseも成功したが、iOS型検査・Core ML推論の成功を示すものではない。

Simulatorには固定の計測メタデータだけを使うメモ編集→再起動復元テストを追加。Debug Simulatorの明示引数に限定し、Release・物理端末では生成しない。macOSのopt-in native smoke testを4話者の固定公開文生成へ拡張した。

[run 42498088478](https://github.com/Guch1120/english_app/actions/runs/42498088478)、commit `b03d7f4`：macOS34 tests成功、4話者の実生成smoke成功（85.804秒）。iOS Simulatorのbuild/analyze・単一起動確認成功、比較メモの再起動復元UIテスト成功（38.617秒）。ただし別の非表示教材UIテストがスイッチをオンにできず、全runは失敗。archiveと音声artifact uploadには進んでいない。実機の追加話者品質と最新headの全必須CIは未確認で、配布はまだ行わない。

## Subsequent merge and device status (2026-11-10)

The initial failed run above is historical. The implementation was subsequently merged in PR [#52](https://github.com/Guch1120/english_app/pull/52); its `quality`, `core`, `ios`, and `review-gate` checks passed in [run 42639013934](https://github.com/Guch1120/english_app/actions/runs/42639013934). The later source-changing PR #66 also passed the macOS build/archive gates, and TestFlight **0.1.0 (160.1)** was installed on iPhone 16. The 160.1 device comparison recorded in [Acceptance.md](Acceptance.md) exercises the default Kokoro Heart and Pocket Alba voices. It does not establish the audible quality of Kokoro Bella/Michael, their install/delete flows, or on-device persistence of comparison notes; those remain unverified.
