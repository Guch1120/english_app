import AVFoundation
import Foundation
import Observation
import SpeechCore
import ModelManagement
import NeuralASRBackends
import DeviceDiagnostics
@preconcurrency import Speech

enum ASREngine: String, CaseIterable, Identifiable, Hashable {
    case parakeet
    case appleSpeech

    var id: String { rawValue }
    var title: String {
        switch self {
        case .parakeet: "Parakeet 110M"
        case .appleSpeech: "Apple Speech (端末内)"
        }
    }
}

@MainActor @Observable final class SpeakingTrainingModel {
    var installed = false
    var recording = false
    var busy = false
    var progress = 0.0
    var status = ""
    var transcript = ""
    var enhancedTranscript = ""
    var enhancedRecordingURL: URL?
    var enhancedProcessingSeconds: Double?
    var audioDuration = 0.0
    var silenceDuration = 0.0
    var pauseCount = 0
    var longestPause = 0.0
    var silenceMetricsAvailable = false
    var processingSeconds: Double?
    var processingPeakMemoryBytes: UInt64?
    var enhancedPeakMemoryBytes: UInt64?
    var error: String?
    var selectedEngine: ASREngine = ASREngine(rawValue: UserDefaults.standard.string(forKey: "asr-engine") ?? "") ?? .parakeet {
        didSet { UserDefaults.standard.set(selectedEngine.rawValue, forKey: "asr-engine") }
    }
    var reuse = REUSETrainingModel()
    var playingRecording = false

    private let recorder = RecorderBox()
    private let appleSpeech = AppleOnDeviceASRBackend()
    private var recordingPlayer: AVAudioPlayer?
    private var playbackMonitor: Task<Void, Never>?
    private var meteringTimer: Timer?
    private var currentPause = 0.0
    private var store: VerifiedModelStore?
    private var recordingURL: URL?
    private var operation: Task<Void, Never>?
    private let coordinator = ModelRuntimeCoordinator.shared
    var appleSpeechAvailable: Bool { appleSpeech.supportsOfflineRecognition }
    var recognitionAvailable: Bool {
        switch selectedEngine {
        case .parakeet: installed
        case .appleSpeech: appleSpeechAvailable
        }
    }

    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("NeuralSpeech")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var protectedRoot = root; try protectedRoot.setResourceValues(values)
            let folder = root.appendingPathComponent("Recordings")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            recordingURL = folder.appendingPathComponent("latest.wav")
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("reuse-latest.wav"))
            store = NeuralASRRuntime.modelStore(root: root)
            if let recordingURL, FileManager.default.fileExists(atPath: recordingURL.path),
               let audio = try? AVAudioFile(forReading: recordingURL) {
                audioDuration = Double(audio.length) / audio.processingFormat.sampleRate
                status = "前回の録音を復元しました。再認識または削除できます。"
            }
        } catch { self.error = "録音とモデルの保存領域を準備できませんでした。" }
        refreshModel()
    }

    func refreshModel() {
        guard let store else { return }
        busy = true; status = "音声認識モデルを確認しています"
        operation = Task {
            defer { busy = false; operation = nil; status = "" }
            do { installed = try await store.isInstalled(ParakeetModel.manifest()) }
            catch { self.error = "Parakeetモデルを確認できませんでした。" }
        }
    }

    func prepareModel() {
        guard !busy, let store else { return }
        busy = true; progress = 0; status = "Parakeetモデルをダウンロードして検証しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let startedAt = Date()
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelDownload, model: .parakeet, outcome: .started, thermalState: .current))
            do {
                let manifest = try ParakeetModel.manifest()
                try await store.install(manifest) { [weak self] fraction in
                    await self?.updateProgress(fraction)
                }
                installed = true; status = "モデルの準備ができました"
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelDownload, model: .parakeet, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), modelBytes: UInt64(max(0, manifest.sizeBytes)), thermalState: .current))
            } catch is CancellationError {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelDownload, model: .parakeet, outcome: .cancelled, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "モデル取得を中断しました。保存済みの途中データから、次回続けてダウンロードします。"
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelDownload, model: .parakeet, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "モデル取得に失敗しました。通信状態を確認して再試行してください。"
            }
        }
    }

    func removeModel() {
        guard !busy, !recording, let store else { return }
        busy = true; status = "Parakeetモデルを削除しています"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil; status = "" }
            do { try await store.remove(ParakeetModel.manifest()); installed = false }
            catch { self.error = "Parakeetモデルを削除できませんでした。" }
        }
    }

    private func updateProgress(_ value: Double) { progress = max(progress, min(1, value)) }

    func startRecording() {
        guard !busy, !recording, recognitionAvailable, let recordingURL else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            busy = true
            defer { busy = false; operation = nil }
            let startedAt = Date()
            let diagnosticModel: DiagnosticModel = selectedEngine == .parakeet ? .parakeet : .appleSpeech
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .started, thermalState: .current))
            guard await AVAudioApplication.requestRecordPermission() else {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "マイクの使用が許可されていません。iPhoneの設定で許可してください。"
                return
            }
            do {
                if selectedEngine == .appleSpeech { try await appleSpeech.load() }
                try Task.checkCancellation()
                stopRecordingPlayback()
                removeEnhancedRecording()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)
                try? FileManager.default.removeItem(at: recordingURL)
                guard try recorder.start(url: recordingURL) else { throw ParakeetASRError.invalidAudio }
                transcript = ""; enhancedTranscript = ""; processingSeconds = nil
                processingPeakMemoryBytes = nil; enhancedPeakMemoryBytes = nil; audioDuration = 0
                silenceDuration = 0; pauseCount = 0; longestPause = 0; currentPause = 0
                silenceMetricsAvailable = false
                recording = true; status = "録音中です。英文を話したら停止してください。"
                startMetering()
            } catch AppleSpeechASRError.permissionDenied {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "Apple Speechの音声認識を許可してください。iPhoneの設定で変更できます。"
            } catch AppleSpeechASRError.offlineRecognitionUnavailable {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "この端末ではApple Speechの端末内認識を利用できません。Parakeetを選択してください。"
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "録音を開始できませんでした。"
            }
        }
    }

    func stopRecording() {
        guard recording else { return }
        stopMetering()
        recorder.stop(); recording = false
        silenceMetricsAvailable = true
        do {
            guard let recordingURL, FileManager.default.fileExists(atPath: recordingURL.path) else {
                throw ParakeetASRError.invalidAudio
            }
            let audio = try AVAudioFile(forReading: recordingURL)
            audioDuration = Double(audio.length) / audio.processingFormat.sampleRate
            status = "録音を保存しました。選択中の音声認識モデルで文字起こしできます。"
            let diagnosticModel: DiagnosticModel = selectedEngine == .parakeet ? .parakeet : .appleSpeech
            Task {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .recording, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(audioDuration * 1000), thermalState: .current))
            }
        } catch { self.error = "録音ファイルを保存できませんでした。" }
    }

    func transcribe() {
        guard !busy, !recording, recognitionAvailable, let recordingURL else { return }
        let engine = selectedEngine
        busy = true; status = "\(engine.title)で文字起こししています"; transcript = ""; processingSeconds = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            let startedAt = Date()
            let diagnosticModel: DiagnosticModel = engine == .parakeet ? .parakeet : .appleSpeech
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .transcription, model: diagnosticModel, outcome: .started, thermalState: .current))
            do {
                let recognition = try await recognize(url: recordingURL, duration: audioDuration, engine: engine)
                transcript = recognition.0
                processingSeconds = recognition.1
                processingPeakMemoryBytes = recognition.2
                status = transcript.isEmpty ? "音声を認識できませんでした。もう一度録音してください。" : "文字起こしが完了しました"
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .transcription, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), peakMemoryBytes: recognition.2, thermalState: .current))
            } catch is CancellationError {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .transcription, model: diagnosticModel, outcome: .cancelled, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                status = "文字起こしを中断しました"
            } catch let error as AppleSpeechASRError {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .transcription, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = error.localizedDescription
            } catch {
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .transcription, model: diagnosticModel, outcome: .failed, elapsedMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1000), thermalState: .current))
                self.error = "文字起こしに失敗しました。録音を残したまま再試行できます。"
            }
        }
    }

    func compareWithREUSE() {
        guard !busy, !recording, audioDuration <= 300, recognitionAvailable, reuse.enabled,
              reuse.installed, reuse.verified,
              let recordingURL else { return }
        let selected = selectedEngine
        let duration = audioDuration
        busy = true; status = "RE-USEなしの音声を文字起こししています"
        transcript = ""; enhancedTranscript = ""; processingSeconds = nil; processingPeakMemoryBytes = nil
        enhancedProcessingSeconds = nil; enhancedPeakMemoryBytes = nil
        reuse.lastMetrics = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do {
                let plain = try await recognize(url: recordingURL, duration: duration, engine: selected)
                transcript = plain.0; processingSeconds = plain.1
                processingPeakMemoryBytes = plain.2
                try Task.checkCancellation()
                status = "RE-USEで音声を強調しています"
                let source = AudioAsset(url: recordingURL, duration: duration, sampleRate: 16_000)
                let enhanced = try await reuse.enhance(source)
                enhancedRecordingURL = enhanced.url
                try Task.checkCancellation()
                status = "RE-USEありの音声を文字起こししています"
                let result = try await recognize(url: enhanced.url, duration: enhanced.duration, engine: selected)
                enhancedTranscript = result.0
                enhancedProcessingSeconds = result.1
                enhancedPeakMemoryBytes = result.2
                status = "RE-USEなし／ありの比較が完了しました"
            } catch is CancellationError { status = "音声比較を中断しました" }
            catch { self.error = "RE-USE比較に失敗しました。元の録音は保持されています。" }
        }
    }

    private func recognize(url: URL, duration: Double, engine: ASREngine) async throws -> (String, Double, UInt64?) {
        let backend: any ASRService
        let diagnosticModel: DiagnosticModel
        let modelBytes: UInt64?
        if engine == .parakeet {
            guard let store else { throw ParakeetASRError.modelUnavailable }
            let manifest = try ParakeetModel.manifest()
            diagnosticModel = .parakeet
            modelBytes = UInt64(max(0, manifest.sizeBytes))
            guard let storageFolder = manifest.storageFolder else { throw ParakeetASRError.modelUnavailable }
            let directory = try await store.directory(manifest)
                .appendingPathComponent("Models").appendingPathComponent(storageFolder)
            backend = NeuralASRRuntime.backend(directory: directory)
        } else {
            backend = appleSpeech
            diagnosticModel = .appleSpeech
            modelBytes = nil
        }
        return try await coordinator.withExclusiveModel { [backend] in
            let memory = ProcessMemorySampler()
            await memory.start()
            let loadStartedAt = Date()
            await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelLoad, model: diagnosticModel, outcome: .started, modelBytes: modelBytes, thermalState: .current))
            do {
                try await backend.load()
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelLoad, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(loadStartedAt) * 1000), modelBytes: modelBytes, thermalState: .current))
                try Task.checkCancellation()
                let start = ContinuousClock().now
                let asset = AudioAsset(url: url, duration: duration, sampleRate: 16_000)
                let result = try await backend.transcribe(asset)
                let elapsed = start.duration(to: .now).components
                let unloadStartedAt = Date()
                await backend.unload()
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelUnload, model: diagnosticModel, outcome: .succeeded, elapsedMilliseconds: Int(Date().timeIntervalSince(unloadStartedAt) * 1000), modelBytes: modelBytes, thermalState: .current))
                let peak = await memory.stop()
                return (result, Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, peak)
            } catch {
                await backend.unload()
                await DiagnosticEventLog.shared.record(DiagnosticEvent(subsystem: .asr, action: .modelUnload, model: diagnosticModel, outcome: .observed, modelBytes: modelBytes, thermalState: .current))
                _ = await memory.stop()
                throw error
            }
        }
    }

    func cancel() {
        operation?.cancel()
        Task { await appleSpeech.cancel() }
        reuse.cancelInference()
        status = "処理を中断しています"
    }
    func playRecording() {
        guard !recording, !busy, let recordingURL else { return }
        playAudio(at: recordingURL)
    }
    func playEnhancedRecording() {
        guard !recording, !busy, let enhancedRecordingURL else { return }
        playAudio(at: enhancedRecordingURL)
    }
    private func playAudio(at url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            recordingPlayer = try AVAudioPlayer(contentsOf: url)
            recordingPlayer?.prepareToPlay()
            guard recordingPlayer?.play() == true else { throw ParakeetASRError.invalidAudio }
            playingRecording = true
            playbackMonitor?.cancel()
            playbackMonitor = Task { [weak self] in
                while let self, self.recordingPlayer?.isPlaying == true {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                }
                self?.playingRecording = false
                self?.playbackMonitor = nil
            }
        } catch { self.error = "録音を再生できませんでした。" }
    }
    func stopRecordingPlayback() {
        playbackMonitor?.cancel(); playbackMonitor = nil
        recordingPlayer?.stop(); recordingPlayer = nil; playingRecording = false
    }
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordMeterSample() }
        }
    }
    private func recordMeterSample() {
        guard recording else { return }
        if recorder.averagePower < -42 {
            silenceDuration += 0.1
            currentPause += 0.1
        } else {
            finishPause()
        }
    }
    private func stopMetering() {
        meteringTimer?.invalidate(); meteringTimer = nil
        finishPause(); currentPause = 0
    }
    private func finishPause() {
        if currentPause >= 0.4 {
            pauseCount += 1
            longestPause = max(longestPause, currentPause)
        }
        currentPause = 0
    }
    func deleteRecording() {
        guard !recording, !busy, let recordingURL else { return }
        do {
            stopRecordingPlayback()
            if FileManager.default.fileExists(atPath: recordingURL.path) { try FileManager.default.removeItem(at: recordingURL) }
            removeEnhancedRecording()
            transcript = ""; enhancedTranscript = ""; processingPeakMemoryBytes = nil
            enhancedProcessingSeconds = nil; enhancedPeakMemoryBytes = nil
            audioDuration = 0; silenceDuration = 0; pauseCount = 0; longestPause = 0
            silenceMetricsAvailable = false; processingSeconds = nil; status = "録音を削除しました"
        } catch { self.error = "録音を削除できませんでした。" }
    }

    private func removeEnhancedRecording() {
        if let enhancedRecordingURL { try? FileManager.default.removeItem(at: enhancedRecordingURL) }
        if let recordingURL {
            let current = recordingURL.deletingLastPathComponent().appendingPathComponent("reuse-latest.wav")
            try? FileManager.default.removeItem(at: current)
        }
        enhancedRecordingURL = nil
    }

    func handleBackground() {
        if recording { stopRecording() }
        if busy { cancel() }
        if reuse.busy { reuse.cancel() }
        stopRecordingPlayback()
    }

    func handleAudioInterruption() {
        if recording { stopRecording() }
        if busy { cancel() }
        if reuse.busy { reuse.cancel() }
        stopRecordingPlayback()
    }

    func handleMemoryWarning() {
        if recording { stopRecording() }
        if busy { cancel() }
        if reuse.busy { reuse.cancel() }
        stopRecordingPlayback()
    }
}

private enum AppleSpeechASRError: LocalizedError {
    case permissionDenied
    case offlineRecognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "音声認識の許可がありません。"
        case .offlineRecognitionUnavailable: "この端末では英語の端末内音声認識を利用できません。"
        }
    }
}

@MainActor private final class AppleOnDeviceASRBackend: ASRService {
    nonisolated let modelID = "apple-speech-en-us-on-device"
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var task: SFSpeechRecognitionTask?

    var supportsOfflineRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition == true
    }

    func load() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw AppleSpeechASRError.permissionDenied }
        guard supportsOfflineRecognition else { throw AppleSpeechASRError.offlineRecognitionUnavailable }
    }

    func unload() async { await cancel() }
    func cancel() async { task?.cancel(); task = nil }

    func transcribe(_ audio: AudioAsset) async throws -> String {
        guard let recognizer, recognizer.isAvailable, supportsOfflineRecognition else {
            throw AppleSpeechASRError.offlineRecognitionUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audio.url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let completion = SpeechRecognitionCompletion(continuation)
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error { completion.finish(.failure(error)); return }
                guard let result, result.isFinal else { return }
                completion.finish(.success(result.bestTranscription.formattedString))
            }
        }
        task = nil
        return result
    }
}

private final class SpeechRecognitionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor private final class RecorderBox {
    private var recorder: AVAudioRecorder?
    func start(url: URL) throws -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let next = try AVAudioRecorder(url: url, settings: settings)
        next.isMeteringEnabled = true
        next.prepareToRecord(); recorder = next
        return next.record()
    }
    var averagePower: Float {
        recorder?.updateMeters()
        return recorder?.averagePower(forChannel: 0) ?? -160
    }
    func stop() { recorder?.stop(); recorder = nil }
}
