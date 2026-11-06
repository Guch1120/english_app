import Foundation
import Observation
import SpeechCore
import ModelManagement
import NeuralTTSBackends
import TTSBackends
import DeviceDiagnostics

@MainActor @Observable final class TTSTrainingModel {
    var selected: String = UserDefaults.standard.string(forKey: "tts-engine") ?? "apple"
    var status = ""
    var progress = 0.0
    var busy = false
    var installed: Set<NeuralVoice> = []
    var measurements: [TTSMeasurement] = []
    var cacheBytes = 0
    var repeats = false { didSet { player.setRepeating(repeats) } }
    var error: String?
    private let speaker: any SpeechPlayback
    private let player = AudioFilePlayback()
    private var cache: TTSAudioCache?
    private var store: VerifiedModelStore?
    private let coordinator = ModelRuntimeCoordinator.shared
    private var operation: Task<Void, Never>?
    private var historyURL: URL?
    init(speaker: any SpeechPlayback) {
        self.speaker = speaker
        do {
            let fm = FileManager.default
            let root = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NeuralSpeech")
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var protectedRoot = root; try protectedRoot.setResourceValues(values)
            store = NeuralRuntime.modelStore(root: root)
            let audio = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("GeneratedSpeech")
            try fm.createDirectory(at: audio, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let storedLimit = UserDefaults.standard.integer(forKey: "tts-cache-mb")
            cache = try TTSAudioCache(directory: audio, maximumBytes: (storedLimit > 0 ? storedLimit : 128) * 1024 * 1024)
            historyURL = root.appendingPathComponent("measurements.json")
            if let data = try? Data(contentsOf: historyURL!) { measurements = (try? JSONDecoder().decode([TTSMeasurement].self, from: data)) ?? [] }
        } catch { self.error = "音声の保存領域を準備できませんでした。" }
        // Saved model selection is checked again against the installed assets.
        busy = true; status = "保存済みモデルを確認しています"
        operation = Task { await refreshModels(); busy = false; operation = nil; status = "" }
    }
    func select(_ engine: String) {
        guard !busy else { return }
        stop(); selected = engine; UserDefaults.standard.set(engine, forKey: "tts-engine")
    }
    func refreshModels() async {
        guard let store else { return }
        var available = Set<NeuralVoice>()
        for voice in NeuralVoice.allCases {
            if let manifest = try? voice.manifest(), (try? await store.isInstalled(manifest)) == true { available.insert(voice) }
        }
        installed = available
        cacheBytes = (try? await cache?.sizeBytes()) ?? 0
    }
    private func updateProgress(_ value: Double) { progress = value }
    func prepare(_ voice: NeuralVoice) {
        guard !busy, let store else { return }
        busy = true; progress = 0; status = "モデルを取得・検証しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let startedAt = Date()
            let diagnosticModel: DiagnosticModel = voice == .kokoro ? .kokoro : .pocket
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelDownload, model: diagnosticModel, outcome: .started, thermalState: .current))
            do {
                let manifest = try voice.manifest()
                try await store.install(manifest) { [weak self] fraction in
                    await self?.updateProgress(fraction)
                }
                try Task.checkCancellation()
                await refreshModels(); status = "モデルの準備が完了しました"
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelDownload, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
            } catch is CancellationError {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelDownload, model: diagnosticModel, outcome: .cancelled, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "取得を中断しました。再試行時は検証済みファイルを再利用します。"
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelDownload, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "モデルを取得・検証できませんでした。通信と空き容量を確認して再試行してください。"; status = "準備に失敗しました"
            }
        }
    }
    func remove(_ voice: NeuralVoice) {
        guard !busy, let store else { return }
        busy = true; stopPlayback()
        operation = Task {
            defer { busy = false; operation = nil }
            let startedAt = Date()
            let diagnosticModel: DiagnosticModel = voice == .kokoro ? .kokoro : .pocket
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelUnload, model: diagnosticModel, outcome: .started, thermalState: .current))
            do {
                try await store.remove(voice.manifest()); installed.remove(voice)
                if selected == voice.id { selected = "apple"; UserDefaults.standard.set(selected, forKey: "tts-engine") }
                status = "モデルを削除しました"
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelUnload, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelUnload, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "モデルを削除できませんでした。"
            }
        }
    }
    private func stopPlayback() { speaker.stop(); player.stop() }
    func speak(_ text: String, speed: Double, engine: String? = nil, comparisonID: UUID? = nil) {
        guard !busy else { return }
        stopPlayback()
        let engine = engine ?? selected
        if engine == "apple" {
            do { try speaker.speak(text, speed: speed); status = "Apple音声を再生しています" }
            catch { self.error = "Apple音声を再生できませんでした。英語音声の設定を確認してください。" }
            return
        }
        guard let voice = NeuralVoice(rawValue: engine), installed.contains(voice), let store, let cache else {
            error = "設定の音声モデル管理から、モデルを準備してください。"; return
        }
        busy = true; progress = 0; status = "モデルを読み込み、音声を生成しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let startedAt = Date()
            let diagnosticModel: DiagnosticModel = voice == .kokoro ? .kokoro : .pocket
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .inference, model: diagnosticModel, outcome: .started, cacheBytes: UInt64(max(0, cacheBytes)), thermalState: .current))
            do {
                let manifest = try voice.manifest()
                let key = TTSCacheKey(text: text, engine: voice.id, modelRevision: "FluidAudio-0.18.2/" + manifest.revision, voice: voice.speaker)
                let asset: AudioAsset
                let measurement: TTSMeasurement
                if let cached = try await cache.lookup(key) {
                    asset = cached
                    measurement = TTSMeasurement(engine: voice.id, voice: voice.speaker, modelRevision: manifest.revision, generationSeconds: nil, asset: asset, cacheHit: true, comparisonID: comparisonID)
                } else {
                    guard try await store.isInstalled(manifest) else { installed.remove(voice); throw NeuralTTSError.modelsMissing }
                    let directory = try await store.directory(manifest)
                    let backend = NeuralRuntime.backend(voice: voice, directory: directory)
                    let result: (Data, Double, UInt64?) = try await coordinator.withExclusiveModel {
                        let monitor = ProcessMemorySampler(); await monitor.start()
                        let loadStartedAt = Date()
                        await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelLoad, model: diagnosticModel, outcome: .started, modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
                        do {
                            try await backend.load()
                            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelLoad, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(loadStartedAt) * 1000), modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
                            try Task.checkCancellation()
                            let clock = ContinuousClock(), start = clock.now
                            let generated = try await backend.synthesize(SpeechRequest(text: key.text, voiceID: voice.speaker))
                            defer { try? FileManager.default.removeItem(at: generated.url) }
                            let data = try Data(contentsOf: generated.url)
                            let components = start.duration(to: clock.now).components
                            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
                            let unloadStartedAt = Date()
                            await backend.unload()
                            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelUnload, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(unloadStartedAt) * 1000), modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
                            return (data,seconds,await monitor.stop())
                        } catch {
                            await backend.unload()
                            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .modelUnload, model: diagnosticModel, outcome: .observed, modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
                            _ = await monitor.stop()
                            throw error
                        }
                    }
                    try Task.checkCancellation()
                    asset = try await cache.store(result.0, key: key)
                    measurement = TTSMeasurement(engine: voice.id, voice: voice.speaker, modelRevision: manifest.revision, generationSeconds: result.1, asset: asset, cacheHit: false, comparisonID: comparisonID, peakProcessRSS: result.2)
                }
                try Task.checkCancellation()
                try player.play(asset, rate: speed, repeating: repeats)
                measurements.insert(measurement, at: 0); measurements = Array(measurements.prefix(100))
                if let historyURL {
                    do { try JSONEncoder().encode(measurements).write(to: historyURL, options: .atomic) }
                    catch { self.error = "音声は再生できますが、測定履歴を保存できませんでした。" }
                }
                cacheBytes = (try? await cache.sizeBytes()) ?? 0
                status = measurement.cacheHit ? "保存済み音声を再生しています" : "生成音声を再生しています"
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .inference, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), peakMemoryBytes: measurement.peakProcessRSS, cacheBytes: UInt64(max(0, cacheBytes)), thermalState: .current))
            } catch is CancellationError {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .inference, model: diagnosticModel, outcome: .cancelled, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "音声生成を中断しました"
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .tts, action: .inference, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "音声を生成・再生できませんでした。モデルの再準備や短い英文での再試行をお試しください。"; status = "音声処理に失敗しました"
            }
        }
    }
    func cancelWork() { if busy { operation?.cancel(); status = "処理の停止を待っています" } }
    func stop() { operation?.cancel(); stopPlayback(); status = busy ? "処理の停止を待っています" : "停止しました" }
    func pause() { speaker.pause(); player.pause() }
    func resume() { speaker.resume(); player.resume() }
    func setRate(_ rate: Double) { player.setRate(rate) }
    func clearCache() {
        guard !busy, let cache else { return }
        stopPlayback(); busy = true
        operation = Task {
            defer { busy = false; operation = nil }
            do { try await cache.clear(); cacheBytes = 0; status = "音声キャッシュを削除しました" }
            catch { self.error = "キャッシュを削除できませんでした。" }
        }
    }
    func clearPersonalData() {
        guard !busy else { return }
        stopPlayback(); busy = true
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                try await cache?.clear(); cacheBytes = 0
                if let historyURL, FileManager.default.fileExists(atPath: historyURL.path) {
                    try FileManager.default.removeItem(at: historyURL)
                }
                if let historyURL {
                    let recordings = historyURL.deletingLastPathComponent().appendingPathComponent("Recordings")
                    if FileManager.default.fileExists(atPath: recordings.path) {
                        try FileManager.default.removeItem(at: recordings)
                    }
                }
                measurements = []
                UserDefaults.standard.removeObject(forKey: "tts-comparison-text")
                UserDefaults.standard.removeObject(forKey: "tts-comparison-group")
                status = "音声と測定履歴を削除しました"
            } catch { self.error = "音声データをすべて削除できませんでした。再度削除してください。" }
        }
    }
    func setCacheLimit(megabytes: Int) {
        guard !busy, let cache else { return }
        busy = true
        operation = Task {
            defer { busy = false; operation = nil }
            do { try await cache.setLimit(megabytes * 1024 * 1024); UserDefaults.standard.set(megabytes, forKey: "tts-cache-mb"); cacheBytes = try await cache.sizeBytes() }
            catch { self.error = "キャッシュ容量を変更できませんでした。" }
        }
    }
}
