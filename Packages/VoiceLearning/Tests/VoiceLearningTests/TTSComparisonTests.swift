import Foundation
import XCTest
import SpeechCore
import NeuralTTSBackends

final class TTSComparisonTests: XCTestCase {
    func testLegacyMeasurementAndLocalNoteRoundTrip() throws {
        let asset = AudioAsset(url: URL(fileURLWithPath: "/tmp/fixed.wav"), duration: 2, sampleRate: 24000)
        let original = TTSMeasurement(engine: "kokoro", voice: "af_heart", modelRevision: "fixed", generationSeconds: 1, asset: asset, cacheHit: false)
        let encoded = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "listeningNote")
        var restored = try JSONDecoder().decode(TTSMeasurement.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.listeningNote)
        try restored.setListeningNote("自然で聞き取りやすい")
        let saved = try JSONDecoder().decode(TTSMeasurement.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(saved.listeningNote, "自然で聞き取りやすい")
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.realTimeFactor, 0.5)
        XCTAssertThrowsError(try restored.setListeningNote(String(repeating: "a", count: 2001)))
        XCTAssertEqual(restored.listeningNote, saved.listeningNote)
        try restored.setListeningNote(" \n ")
        XCTAssertNil(restored.listeningNote)
    }

    func testOptionalSpeakersHaveSeparatePinnedStorageAndCacheIdentity() throws {
        let base = try NeuralVoice.kokoro.manifest()
        let extras = NeuralSpeaker.allCases.compactMap(\.supplementalManifest)
        XCTAssertEqual(extras.count, 2)
        for manifest in extras {
            try manifest.validate()
            XCTAssertEqual(manifest.revision, base.revision)
            XCTAssertNotEqual(manifest.id, base.id)
            XCTAssertNotEqual(manifest.storageFolder, base.storageFolder)
            XCTAssertEqual(manifest.files.count, 1)
        }
        XCTAssertEqual(Set(extras.map(\.id)).count, 2)
        XCTAssertEqual(Set(extras.compactMap(\.storageFolder)).count, 2)
        let heart = TTSCacheKey(text: "Please listen.", engine: "kokoro", modelRevision: base.revision, voice: NeuralSpeaker.heart.id)
        let bella = TTSCacheKey(text: "Please listen.", engine: "kokoro", modelRevision: base.revision, voice: NeuralSpeaker.bella.id)
        XCTAssertNotEqual(heart, bella)
        XCTAssertEqual(NeuralSpeaker.alba.engine, .pocket)
    }
}
