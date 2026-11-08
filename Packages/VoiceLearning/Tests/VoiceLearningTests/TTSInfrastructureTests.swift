import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SpeechCore
@testable import ModelManagement
import NeuralTTSBackends

final class TTSInfrastructureTests: XCTestCase, @unchecked Sendable {
    private actor ProgressRecorder {
        private(set) var values: [Double] = []
        func append(_ value: Double) { values.append(value) }
    }

    private actor PartialTransferRecorder {
        private(set) var offsets: [Int64] = []
        private(set) var paths: [String] = []
        func record(path: String, offset: Int64) -> Int {
            offsets.append(offset)
            paths.append(path)
            return offsets.count
        }
        func state() -> (offsets: [Int64], paths: [String]) { (offsets, paths) }
    }

    private struct NoopDownloadProgress: ModelDownloadProgress {
        func report(bytesReceived: Int64) async { }
    }

    private final class RangeRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?] = []
        func record(_ value: String?) { lock.withLock { values.append(value) } }
        func snapshot() -> [String?] { lock.withLock { values } }
        func reset() { lock.withLock { values = [] } }
    }

    private final class ModelRangeURLProtocol: URLProtocol, @unchecked Sendable {
        static let recorder = RangeRequestRecorder()
        private static let payload = Data("abcdefghij".utf8)

        override class func canInit(with request: URLRequest) -> Bool {
            ["interrupt.test", "ignore.test"].contains(request.url?.host ?? "")
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let range = request.value(forHTTPHeaderField: "Range")
            Self.recorder.record(range)
            let isInterruptedFirstAttempt = request.url?.host == "interrupt.test" && range == nil
            let ignoresRange = request.url?.host == "ignore.test"
            let response: HTTPURLResponse
            let body: Data

            if let range, !ignoresRange,
               let offsetText = range.dropFirst("bytes=".count).split(separator: "-").first,
               let offset = Int(offsetText), offset < Self.payload.count {
                body = Data(Self.payload.suffix(from: offset))
                response = HTTPURLResponse(
                    url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Range": "bytes \(offset)-\(Self.payload.count - 1)/\(Self.payload.count)",
                        "Content-Length": "\(body.count)"
                    ]
                )!
            } else {
                body = Self.payload
                response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "\(body.count)"]
                )!
            }

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if isInterruptedFirstAttempt {
                client?.urlProtocol(self, didLoad: Data(body.prefix(4)))
                // Let URLSession deliver the buffered bytes to its delegate before simulating a dropped connection.
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self else { return }
                    self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                }
            } else {
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() { }
    }

    static func wav(samples: Int = 240) -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) { for shift in [0,8,16,24] { data.append(UInt8((value >> shift) & 255)) } }
        text("RIFF"); u32(UInt32(36 + samples*2)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(24000); u32(48000); u16(2); u16(16); text("data"); u32(UInt32(samples*2))
        data.append(Data(repeating: 1,count: samples*2)); return data
    }
    func testWAVRejectsTruncationAndReadsDuration() throws {
        let info = try WAVInfo(data: Self.wav())
        XCTAssertEqual(info.sampleRate,24000); XCTAssertEqual(info.duration,0.01,accuracy:0.000001)
        XCTAssertThrowsError(try WAVInfo(data: Self.wav().dropLast()))
        XCTAssertThrowsError(try WAVInfo(data: Data("not audio".utf8)))
    }
    func testCacheSeparatesVoiceRevisionAndParametersAndSurvivesRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = TTSCacheKey(text:"  Hello\nworld! ",engine:"kokoro",modelRevision:"r1",voice:"a")
        let cache = try TTSAudioCache(directory:root)
        _ = try await cache.store(Self.wav(),key:key)
        let reopened = try TTSAudioCache(directory:root)
        let hit = try await reopened.lookup(TTSCacheKey(text:"Hello world!",engine:"kokoro",modelRevision:"r1",voice:"a"))
        XCTAssertNotNil(hit)
        for miss in [TTSCacheKey(text:key.text,engine:"kokoro",modelRevision:"r2",voice:"a"),
                     TTSCacheKey(text:key.text,engine:"kokoro",modelRevision:"r1",voice:"b"),
                     TTSCacheKey(text:key.text,engine:"kokoro",modelRevision:"r1",voice:"a",parameters:["temperature":"0.5"])] {
            let result = try await reopened.lookup(miss); XCTAssertNil(result)
        }
        try Data("corrupted".utf8).write(to: hit!.url)
        let corrupt = try await reopened.lookup(key); XCTAssertNil(corrupt)
    }
    func testCacheEvictsOldEntriesAndClearDoesNotTouchSiblingData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories:true)
        let sibling = root.appendingPathComponent("learning.sqlite"); try Data([1]).write(to:sibling)
        let cache = try TTSAudioCache(directory:root.appendingPathComponent("audio"),maximumBytes:1200)
        for text in ["one","two","three"] {
            _ = try await cache.store(Self.wav(),key:TTSCacheKey(text:text,engine:"k",modelRevision:"r",voice:"a"))
        }
        let size = try await cache.sizeBytes(); XCTAssertLessThanOrEqual(size,1200)
        let old = try await cache.lookup(TTSCacheKey(text:"one",engine:"k",modelRevision:"r",voice:"a")); XCTAssertNil(old)
        try await cache.clear(); XCTAssertTrue(FileManager.default.fileExists(atPath:sibling.path))
    }
    func testCuratedManifestsHaveImmutableFilesAndLicensedVoiceSubset() throws {
        for voice in NeuralVoice.allCases {
            let manifest = try voice.manifest(); try manifest.validate()
            XCTAssertGreaterThan(manifest.sizeBytes,0)
            for file in manifest.files {
                XCTAssertEqual(try manifest.downloadURL(for:file).host,"huggingface.co")
                XCTAssertTrue(try manifest.downloadURL(for:file).path.contains(manifest.revision))
            }
        }
        let pocket = try NeuralVoice.pocket.manifest()
        XCTAssertEqual(pocket.storageFolder, "pocket-tts")
        XCTAssertEqual(pocket.files.filter { $0.path.hasSuffix(".safetensors") }.map(\.path),["v2.1/english/constants_bin/alba.safetensors"])
    }
    func testUntrustedManifestCannotEscapeStorageOrChooseAnotherHost() {
        for path in ["../private.key","/absolute","x/../y","x//y","https://example.com/x","%2e%2e/x","x\\y"] {
            let manifest = ModelManifest(id:"test",repository:"a/b",revision:String(repeating:"a",count:40),
                                         files:[ModelFile(path:path,sha256:String(repeating:"b",count:64),size:1)])
            XCTAssertThrowsError(try manifest.validate(),path)
        }
    }
    func testStorageFolderCannotEscapeModelRoot() {
        for folder in ["..", "../escape", "/absolute", "x/y", "x%2fy", "x\\y"] {
            let manifest = ModelManifest(id: "test", repository: "a/b", revision: String(repeating: "a", count: 40),
                files: [ModelFile(path: "model.bin", sha256: String(repeating: "b", count: 64), size: 1)], storageFolder: folder)
            XCTAssertThrowsError(try manifest.validate())
        }
    }
    func testModelStoreRejectsBadDigestAndKeepsOnlyVerifiedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let digest = String(repeating:"b",count:64)
        let manifest = ModelManifest(id:"test",repository:"a/b",revision:String(repeating:"a",count:40),files:[ModelFile(path:"model.bin",sha256:digest,size:4)])
        let bad = VerifiedModelStore(root:root,download:{ _, url, _, _ in try Data("evil".utf8).write(to:url) },sha256:{ _ in String(repeating:"c",count:64) })
        do { try await bad.install(manifest,progress:{ _ in }); XCTFail("Unverified model accepted") } catch ModelInstallError.invalidChecksum { }
        let absent = try await bad.isInstalled(manifest); XCTAssertFalse(absent)
        let good = VerifiedModelStore(root:root,download:{ _,url,_,_ in try Data("good".utf8).write(to:url) },sha256:{ url in
            String(decoding:try Data(contentsOf:url),as:UTF8.self) == "good" ? digest : "invalid"
        })
        try await good.install(manifest,progress:{ _ in })
        let ready = try await good.isInstalled(manifest); XCTAssertTrue(ready)
        let noNetwork = VerifiedModelStore(root:root,download:{ _,_,_,_ in throw URLError(.notConnectedToInternet) },sha256:{ _ in digest })
        try await noNetwork.install(manifest,progress:{ _ in })
        try await noNetwork.remove(manifest)
        let removed = try await noNetwork.isInstalled(manifest); XCTAssertFalse(removed)
    }

    func testModelStoreReportsMonotonicByteProgressWithinLargeFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let digest = String(repeating: "b", count: 64)
        let manifest = ModelManifest(
            id: "test", repository: "a/b", revision: String(repeating: "a", count: 40),
            files: [ModelFile(path: "model.bin", sha256: digest, size: 8)]
        )
        let recorder = ProgressRecorder()
        let store = VerifiedModelStore(root: root, download: { _, url, _, report in
            try Data("verified".utf8).write(to: url)
            for received in [1, 3, 5, 8] { await report.report(bytesReceived: Int64(received)) }
        }, sha256: { _ in digest })

        try await store.install(manifest) { value in await recorder.append(value) }
        let values = await recorder.values
        XCTAssertEqual(values, [0.125, 0.375, 0.625, 0.99, 1.0])
    }
}

extension TTSInfrastructureTests {
    func testRangeResponseValidationAcceptsResumeAndFullRestart() throws {
        XCTAssertEqual(try ModelDownloadResponsePlan.firstByte(
            statusCode: 206, contentRange: "bytes 4-9/10", requestedOffset: 4, expectedSize: 10
        ), 4)
        XCTAssertEqual(try ModelDownloadResponsePlan.firstByte(
            statusCode: 200, contentRange: nil, requestedOffset: 4, expectedSize: 10
        ), 0)
        XCTAssertThrowsError(try ModelDownloadResponsePlan.firstByte(
            statusCode: 206, contentRange: "bytes 3-9/10", requestedOffset: 4, expectedSize: 10
        ))
        XCTAssertThrowsError(try ModelDownloadResponsePlan.firstByte(
            statusCode: 206, contentRange: "bytes 4-9/11", requestedOffset: 4, expectedSize: 10
        ))
    }

    func testURLSessionDownloaderResumesPartialAndRestartsWhenRangeIsIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelRangeURLProtocol.self]
        let interruptedFile = root.appendingPathComponent("interrupted.partial")
        let url = URL(string: "https://interrupt.test/model.bin")!

        do {
            try await URLSessionModelDownloader.download(
                from: url, to: interruptedFile, expectedSize: 10,
                progress: NoopDownloadProgress(), sessionConfiguration: configuration
            )
            XCTFail("The first response should simulate a dropped connection")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: interruptedFile), Data("abcd".utf8))

        try await URLSessionModelDownloader.download(
            from: url, to: interruptedFile, expectedSize: 10,
            progress: NoopDownloadProgress(), sessionConfiguration: configuration
        )
        XCTAssertEqual(try Data(contentsOf: interruptedFile), Data("abcdefghij".utf8))
        XCTAssertEqual(ModelRangeURLProtocol.recorder.snapshot(), [nil, "bytes=4-"])

        ModelRangeURLProtocol.recorder.reset()
        let ignoredFile = root.appendingPathComponent("ignored.partial")
        try Data("abcd".utf8).write(to: ignoredFile)
        try await URLSessionModelDownloader.download(
            from: URL(string: "https://ignore.test/model.bin")!, to: ignoredFile, expectedSize: 10,
            progress: NoopDownloadProgress(), sessionConfiguration: configuration
        )
        XCTAssertEqual(try Data(contentsOf: ignoredFile), Data("abcdefghij".utf8))
        XCTAssertEqual(ModelRangeURLProtocol.recorder.snapshot(), ["bytes=4-"])
    }

    func testInterruptedFileTransferKeepsPartialAndContinuesFromItsOffset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = Data("abcdefghij".utf8)
        let digest = String(repeating: "a", count: 64)
        let manifest = ModelManifest(
            id: "resume", repository: "a/b", revision: String(repeating: "b", count: 40),
            files: [ModelFile(path: "model.bin", sha256: digest, size: Int64(contents.count))]
        )
        let recorder = PartialTransferRecorder()
        let progress = ProgressRecorder()
        let store = VerifiedModelStore(root: root, download: { _, url, expectedSize, report in
            XCTAssertEqual(expectedSize, Int64(contents.count))
            let existingSize = ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize).map(Int64.init) ?? 0
            let attempt = await recorder.record(path: url.path, offset: existingSize)
            if attempt == 1 {
                try Data(contents.prefix(4)).write(to: url)
                await report.report(bytesReceived: 4)
                throw CancellationError()
            }

            XCTAssertEqual(existingSize, 4)
            await report.report(bytesReceived: existingSize)
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: contents.suffix(from: Int(existingSize)))
            try handle.close()
            await report.report(bytesReceived: Int64(contents.count))
        }, sha256: { url in
            try Data(contentsOf: url) == contents ? digest : String(repeating: "c", count: 64)
        })

        do {
            try await store.install(manifest) { value in await progress.append(value) }
            XCTFail("The first transfer should be interrupted")
        } catch is CancellationError { }

        try await store.install(manifest) { value in await progress.append(value) }
        let state = await recorder.state()
        XCTAssertEqual(state.offsets, [0, 4])
        XCTAssertEqual(state.paths.count, 2)
        XCTAssertEqual(state.paths[0], state.paths[1])
        let installed = try await store.isInstalled(manifest)
        XCTAssertTrue(installed)
        let values = await progress.values
        XCTAssertEqual(values.last, 1.0)
        XCTAssertTrue(values.contains(0.4))
    }

    func testCompletePartialIsVerifiedAndPromotedAfterInterruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = Data("complete".utf8)
        let digest = String(repeating: "d", count: 64)
        let manifest = ModelManifest(
            id: "promote", repository: "a/b", revision: String(repeating: "c", count: 40),
            files: [ModelFile(path: "model.bin", sha256: digest, size: Int64(contents.count))]
        )
        let recorder = PartialTransferRecorder()
        let first = VerifiedModelStore(root: root, download: { _, url, _, _ in
            _ = await recorder.record(path: url.path, offset: 0)
            try contents.write(to: url)
            throw CancellationError()
        }, sha256: { url in
            try Data(contentsOf: url) == contents ? digest : String(repeating: "e", count: 64)
        })

        do {
            try await first.install(manifest, progress: { _ in })
            XCTFail("The first attempt should stop before promotion")
        } catch is CancellationError { }

        let retry = VerifiedModelStore(root: root, download: { _, _, _, _ in
            XCTFail("A complete partial must be verified and promoted without a network request")
            throw URLError(.badURL)
        }, sha256: { url in
            try Data(contentsOf: url) == contents ? digest : String(repeating: "e", count: 64)
        })
        try await retry.install(manifest, progress: { _ in })
        let installed = try await retry.isInstalled(manifest)
        XCTAssertTrue(installed)
        let state = await recorder.state()
        XCTAssertEqual(state.offsets, [0])
    }

    func testInterruptedDownloadResumesWithoutDownloadingVerifiedFileAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let digest=String(repeating:"b",count:64)
        let manifest=ModelManifest(id:"test",repository:"a/b",revision:String(repeating:"a",count:40),
            files:["one.bin","two.bin"].map { ModelFile(path:$0,sha256:digest,size:4) })
        let first=VerifiedModelStore(root:root,download:{ remote,url,_,_ in
            if remote.lastPathComponent == "two.bin" { throw CancellationError() }
            try Data("good".utf8).write(to:url)
        },sha256:{ _ in digest })
        do { try await first.install(manifest,progress:{ _ in }); XCTFail() } catch is CancellationError { }
        let partial=try await first.isInstalled(manifest); XCTAssertFalse(partial)
        let retry=VerifiedModelStore(root:root,download:{ remote,url,_,_ in
            if remote.lastPathComponent == "one.bin" { throw URLError(.badURL) }
            try Data("good".utf8).write(to:url)
        },sha256:{ _ in digest })
        try await retry.install(manifest,progress:{ _ in })
        let complete=try await retry.isInstalled(manifest); XCTAssertTrue(complete)
    }
}
