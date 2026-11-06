import Foundation
import XCTest
@testable import SpeechCore
import ModelManagement
import NeuralTTSBackends

final class TTSInfrastructureTests: XCTestCase, @unchecked Sendable {
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
        let bad = VerifiedModelStore(root:root,download:{ _, url in try Data("evil".utf8).write(to:url) },sha256:{ _ in String(repeating:"c",count:64) })
        do { try await bad.install(manifest,progress:{ _ in }); XCTFail("Unverified model accepted") } catch ModelInstallError.invalidChecksum { }
        let absent = try await bad.isInstalled(manifest); XCTAssertFalse(absent)
        let good = VerifiedModelStore(root:root,download:{ _,url in try Data("good".utf8).write(to:url) },sha256:{ url in
            String(decoding:try Data(contentsOf:url),as:UTF8.self) == "good" ? digest : "invalid"
        })
        try await good.install(manifest,progress:{ _ in })
        let ready = try await good.isInstalled(manifest); XCTAssertTrue(ready)
        let noNetwork = VerifiedModelStore(root:root,download:{ _,_ in throw URLError(.notConnectedToInternet) },sha256:{ _ in digest })
        try await noNetwork.install(manifest,progress:{ _ in })
        try await noNetwork.remove(manifest)
        let removed = try await noNetwork.isInstalled(manifest); XCTAssertFalse(removed)
    }
}

extension TTSInfrastructureTests {
    func testInterruptedDownloadResumesWithoutDownloadingVerifiedFileAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let digest=String(repeating:"b",count:64)
        let manifest=ModelManifest(id:"test",repository:"a/b",revision:String(repeating:"a",count:40),
            files:["one.bin","two.bin"].map { ModelFile(path:$0,sha256:digest,size:4) })
        let first=VerifiedModelStore(root:root,download:{ remote,url in
            if remote.lastPathComponent == "two.bin" { throw CancellationError() }
            try Data("good".utf8).write(to:url)
        },sha256:{ _ in digest })
        do { try await first.install(manifest,progress:{ _ in }); XCTFail() } catch is CancellationError { }
        let partial=try await first.isInstalled(manifest); XCTAssertFalse(partial)
        let retry=VerifiedModelStore(root:root,download:{ remote,url in
            if remote.lastPathComponent == "one.bin" { throw URLError(.badURL) }
            try Data("good".utf8).write(to:url)
        },sha256:{ _ in digest })
        try await retry.install(manifest,progress:{ _ in })
        let complete=try await retry.isInstalled(manifest); XCTAssertTrue(complete)
    }
}
