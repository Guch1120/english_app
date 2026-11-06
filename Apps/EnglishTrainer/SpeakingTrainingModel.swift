import AVFoundation
import Foundation
import Observation
import SpeechCore
import ModelManagement
import NeuralASRBackends
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
    var audioDuration = 0.0
    var silenceDuration = 0.0
    var pauseCount = 0
    var longestPause = 0.0
    var silenceMetricsAvailable = false
    var processingSeconds: Double?
    var error: String?
    var selectedEngine: ASREngine = ASREngine(rawValue: UserDefaults.standard.string(forKey: "asr-engine") ?? "") ?? .parakeet {
        didSet { UserDefaults.standard.set(selectedEngine.rawValue, forKey: "asr-engine") }
    }
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
    var recognitionAvailable: Bool {
        switch selectedEngine {
        case .parakeet: installed
        case .appleSpeech: appleSpeech.supportsOfflineRecognition
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
            defer { busy = false; operation = nil; status = "" }
            do {
                try await store.install(ParakeetModel.manifest()) { [weak self] fraction in
                    await self?.updateProgress(fraction)
                }
                installed = true; status = "モデルの準備ができました"
            } catch is CancellationError { status = "モデル取得を中断しました" }
            catch { self.error = "モデル取得に失敗しました。通信状態を確認して再試行してください。" }
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

    private func updateProgress(_ value: Double) { progress = value }

    func startRecording() {
        guard !busy, !recording, recognitionAvailable, let recordingURL else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            busy = true
            defer { busy = false; operation = nil }
            guard await AVAudioApplication.requestRecordPermission() else {
                status = "マイクの使用が許可されていません。iPhoneの設定で許可してください。"
                return
            }
            do {
                if selectedEngine == .appleSpeech { try await appleSpeech.load() }
                try Task.checkCancellation()
                stopRecordingPlayback()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)
                try? FileManager.default.removeItem(at: recordingURL)
                guard try recorder.start(url: recordingURL) else { throw ParakeetASRError.invalidAudio }
                transcript = ""; processingSeconds = nil; audioDuration = 0
                silenceDuration = 0; pauseCount = 0; longestPause = 0; currentPause = 0
                silenceMetricsAvailable = false
                recording = true; status = "録音中です。英文を話したら停止してください。"
                startMetering()
            } catch AppleSpeechASRError.permissionDenied {
                status = "Apple Speechの音声認識を許可してください。iPhoneの設定で変更できます。"
            } catch AppleSpeechASRError.offlineRecognitionUnavailable {
                status = "この端末ではApple Speechの端末内認識を利用できません。Parakeetを選択してください。"
            } catch { self.error = "録音を開始できませんでした。" }
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
        } catch { self.error = "録音ファイルを保存できませんでした。" }
    }

    func transcribe() {
        guard !busy, !recording, recognitionAvailable, let recordingURL else { return }
        let engine = selectedEngine
        busy = true; status = "\(engine.title)で文字起こししています"; transcript = ""; processingSeconds = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do {
                let backend: any ASRService
                if engine == .parakeet {
                    guard let store else { throw ParakeetASRError.modelUnavailable }
                    let manifest = try ParakeetModel.manifest()
                    guard let storageFolder = manifest.storageFolder else { throw ParakeetASRError.modelUnavailable }
                    let directory = try await store.directory(manifest)
                        .appendingPathComponent("Models").appendingPathComponent(storageFolder)
                    backend = NeuralASRRuntime.backend(directory: directory)
                } else {
                    backend = appleSpeech
                }
                let duration = audioDuration
                let recognition = try await coordinator.withExclusiveModel { [backend] in
                    try await backend.load()
                    do {
                        try Task.checkCancellation()
                        let start = ContinuousClock().now
                        let audio = AudioAsset(url: recordingURL, duration: duration, sampleRate: 16_000)
                        let result = try await backend.transcribe(audio)
                        let duration = start.duration(to: ContinuousClock().now).components
                        await backend.unload()
                        return (result, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
                    } catch { await backend.unload(); throw error }
                }
                transcript = recognition.0
                processingSeconds = recognition.1
                status = transcript.isEmpty ? "音声を認識できませんでした。もう一度録音してください。" : "文字起こしが完了しました"
            } catch is CancellationError { status = "文字起こしを中断しました" }
            catch let error as AppleSpeechASRError { self.error = error.localizedDescription }
            catch { self.error = "文字起こしに失敗しました。録音を残したまま再試行できます。" }
        }
    }

    func cancel() {
        operation?.cancel()
        Task { await appleSpeech.cancel() }
        status = "処理を中断しています"
    }
    func playRecording() {
        guard !recording, !busy, let recordingURL else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            recordingPlayer = try AVAudioPlayer(contentsOf: recordingURL)
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
            transcript = ""; audioDuration = 0; silenceDuration = 0; pauseCount = 0; longestPause = 0
            silenceMetricsAvailable = false; processingSeconds = nil; status = "録音を削除しました"
        } catch { self.error = "録音を削除できませんでした。" }
    }

    func handleBackground() {
        if recording { stopRecording() }
        if busy { cancel() }
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
