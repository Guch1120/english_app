import AVFoundation
import Foundation
import Observation
import SpeechCore
import ModelManagement
import NeuralASRBackends

@MainActor @Observable final class SpeakingTrainingModel {
    var installed = false
    var recording = false
    var busy = false
    var progress = 0.0
    var status = ""
    var transcript = ""
    var audioDuration = 0.0
    var processingSeconds: Double?
    var error: String?

    private let recorder = RecorderBox()
    private var store: VerifiedModelStore?
    private var recordingURL: URL?
    private var operation: Task<Void, Never>?
    private let coordinator = ModelRuntimeCoordinator.shared

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
        } catch { self.error = "録音とモデルの保存領域を準備できませんでした。" }
        refreshModel()
    }

    func refreshModel() {
        guard let store else { return }
        busy = true; status = "Parakeetモデルを確認しています"
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
        guard !busy, !recording, let recordingURL else { return }
        operation = Task { [weak self] in
            guard let self else { return }
            busy = true
            defer { busy = false; operation = nil }
            guard await AVAudioApplication.requestRecordPermission() else {
                status = "マイクの使用が許可されていません。iPhoneの設定で許可してください。"
                return
            }
            do {
                try Task.checkCancellation()
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)
                try? FileManager.default.removeItem(at: recordingURL)
                guard recorder.start(url: recordingURL) else { throw ParakeetASRError.invalidAudio }
                transcript = ""; processingSeconds = nil; audioDuration = 0
                recording = true; status = "録音中です。英文を話したら停止してください。"
            } catch { self.error = "録音を開始できませんでした。" }
        }
    }

    func stopRecording() {
        guard recording else { return }
        recorder.stop(); recording = false
        do {
            guard let recordingURL, FileManager.default.fileExists(atPath: recordingURL.path) else {
                throw ParakeetASRError.invalidAudio
            }
            let audio = try AVAudioFile(forReading: recordingURL)
            audioDuration = Double(audio.length) / audio.processingFormat.sampleRate
            status = "録音を保存しました。Parakeetで文字起こしできます。"
        } catch { self.error = "録音ファイルを保存できませんでした。" }
    }

    func transcribe() {
        guard !busy, !recording, installed, let store, let recordingURL else { return }
        busy = true; status = "Parakeetで文字起こししています"; transcript = ""; processingSeconds = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { busy = false; operation = nil }
            do {
                let manifest = try ParakeetModel.manifest()
                guard let storageFolder = manifest.storageFolder else { throw ParakeetASRError.modelUnavailable }
                let directory = try await store.directory(manifest)
                    .appendingPathComponent("Models").appendingPathComponent(storageFolder)
                let backend = NeuralASRRuntime.backend(directory: directory)
                let recognition = try await coordinator.withExclusiveModel { [backend] in
                    try await backend.load()
                    do {
                        try Task.checkCancellation()
                        let start = ContinuousClock().now
                        let audio = AudioAsset(url: recordingURL, duration: audioDuration, sampleRate: 16_000)
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
            catch { self.error = "文字起こしに失敗しました。録音を残したまま再試行できます。" }
        }
    }

    func cancel() { operation?.cancel(); status = "処理を中断しています" }
    func deleteRecording() {
        guard !recording, !busy, let recordingURL else { return }
        do {
            if FileManager.default.fileExists(atPath: recordingURL.path) { try FileManager.default.removeItem(at: recordingURL) }
            transcript = ""; audioDuration = 0; processingSeconds = nil; status = "録音を削除しました"
        } catch { error = "録音を削除できませんでした。" }
    }

    func handleBackground() {
        if recording { stopRecording() }
        if busy { cancel() }
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
        next.prepareToRecord(); recorder = next
        return next.record()
    }
    func stop() { recorder?.stop(); recorder = nil }
}
