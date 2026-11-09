import Foundation
import XCTest
import ModelManagement
import AudioEnhancementBackends

final class ModelInformationTests: XCTestCase, @unchecked Sendable {
    func testREUSEMetadataUsesValidatedPackWithoutEnablingAnEngine() throws {
        let manifest = try REUSECatalogInformation.manifest()
        try manifest.validate()
        XCTAssertEqual(manifest.sizeBytes, 54_206_689)
        XCTAssertEqual(manifest.repository, "AILogDev/RE-USE-MLX-CoreML")
        XCTAssertEqual(manifest.revision, "4b7e50680ba34f10865cab7e24054262596f5ab4")
        XCTAssertTrue(manifest.files.allSatisfy { $0.path.hasSuffix(".bin") || $0.path.hasSuffix(".json") || $0.path.hasSuffix(".mlmodel") || $0.path.hasSuffix(".mlx") || $0.path.hasSuffix(".safetensors") })
    }
    func testLegacyDescriptorDoesNotInventMissingMetadataOrVerification() throws {
        let json = Data(#"{"id":"old","name":"Old model","kind":"tts","runtime":"Core ML"}"#.utf8)
        let legacy = try JSONDecoder().decode(ModelDescriptor.self, from: json)
        XCTAssertFalse(legacy.verifiedOnDevice)
        XCTAssertNil(legacy.developer)
        XCTAssertNil(legacy.sizeBytes)
        XCTAssertNil(legacy.manifest)
        XCTAssertTrue(legacy.languages.isEmpty)
        let file = ModelFile(path: "model.bin", sha256: String(repeating: "a", count: 64), size: 12)
        let manifest = ModelManifest(id: "fixed", repository: "example/model", revision: String(repeating: "b", count: 40), files: [file])
        let descriptor = ModelDescriptor(id: "fixed", name: "Fixed model", kind: .tts, runtime: "Core ML", developer: "Example",
            languages: ["en-US"], version: manifest.revision, minimumOS: "iOS 18", license: "Apache-2.0",
            capabilities: ["speech synthesis"], manifest: manifest, downloadSource: URL(string: "https://example.com/model"),
            verificationSummary: "Not verified on device")
        let restored = try JSONDecoder().decode(ModelDescriptor.self, from: JSONEncoder().encode(descriptor))
        XCTAssertEqual(restored.sizeBytes, 12)
        XCTAssertEqual(restored.manifest?.files.first?.sha256, file.sha256)
        XCTAssertEqual(restored.version, manifest.revision)
        XCTAssertEqual(restored.languages, ["en-US"])
        XCTAssertFalse(restored.verifiedOnDevice)
    }

    func testLeaseStateAndFailureDoNotPretendModelWasUnloaded() async throws {
        enum Failure: Error { case expected }
        let runtime = ModelRuntimeCoordinator()
        do {
            let _: Int = try await runtime.withExclusiveModel(modelID: "fixed") {
                await runtime.didLoad("fixed")
                let during = await runtime.snapshot()
                XCTAssertEqual(during.activeModelID, "fixed")
                XCTAssertTrue(during.loadedModelIDs.contains("fixed"))
                throw Failure.expected
            }
            XCTFail("Operation must fail")
        } catch Failure.expected { }
        let failed = await runtime.snapshot()
        XCTAssertNil(failed.activeModelID)
        XCTAssertEqual(failed.failures["fixed"], .operationFailed)
        XCTAssertTrue(failed.loadedModelIDs.contains("fixed"), "A failed lease is not proof of SDK cleanup")
        await runtime.didUnload("fixed")
        _ = try await runtime.withExclusiveModel(modelID: "fixed") { 1 }
        let recovered = await runtime.snapshot()
        XCTAssertFalse(recovered.loadedModelIDs.contains("fixed"))
        XCTAssertNil(recovered.failures["fixed"])
        do {
            let _: Int = try await runtime.withExclusiveModel(modelID: "cancelled") { throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
        let cancelled = await runtime.snapshot()
        XCTAssertNil(cancelled.activeModelID)
        XCTAssertNil(cancelled.failures["cancelled"])
        let wrappedCancellation = Task {
            let _: Int = try await runtime.withExclusiveModel(modelID: "wrapped-cancel") {
                withUnsafeCurrentTask { $0?.cancel() }
                throw Failure.expected
            }
        }
        do { try await wrappedCancellation.value; XCTFail("SDK cancellation must propagate") }
        catch is CancellationError { }
        let afterWrappedCancellation = await runtime.snapshot()
        XCTAssertNil(afterWrappedCancellation.failures["wrapped-cancel"])
        XCTAssertNil(afterWrappedCancellation.activeModelID)
    }
}
