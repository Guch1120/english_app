import Foundation
import LLMCore
import ModelManagement
import DeviceDiagnostics
#if canImport(LiteRTLM)
import LiteRTLM
#endif

public enum LiteRTLLMError: Error, Equatable {
    case modelMissing
    case runtimeUnavailable
}

/// A single-model, on-device Gemma-capable service. Callers hold the shared model lease for the
/// complete load/generate/unload operation so TTS and ASR cannot compete for peak memory.
public actor LiteRTLLMService: ManagedLLMService {
    private var modelURL: URL?
    private var trackedModelID: String?
    private var loadSeconds: Double?
    private var latestMetrics: LLMInferenceMetrics?
    private let memorySampler = ProcessMemorySampler()
    #if canImport(LiteRTLM)
    private var engine: Engine?
    private var conversation: Conversation?
    #endif

    public init() {}

    public func load(modelURL: URL) async throws {
        try await load(modelURL: modelURL, modelID: modelURL.lastPathComponent)
    }

    public func load(modelURL: URL, modelID: String) async throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw LiteRTLLMError.modelMissing }
        guard self.modelURL != modelURL || trackedModelID != modelID else { return }
        await unload()
        let started = ContinuousClock.now
        #if canImport(LiteRTLM)
        // LiteRT-LM 0.19.1 exposes decode throughput through its experimental benchmark API.
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableBenchmark = true
        let config = try EngineConfig(modelPath: modelURL.path, backend: .gpu, maxNumTokens: 2048)
        let loaded = Engine(engineConfig: config)
        try await loaded.initialize()
        engine = loaded
        self.modelURL = modelURL
        trackedModelID = modelID
        await ModelRuntimeCoordinator.shared.didLoad(modelID)
        loadSeconds = started.duration(to: .now).seconds
        #else
        throw LiteRTLLMError.runtimeUnavailable
        #endif
    }

    public func generate(prompt: String) async throws -> String {
        guard let modelURL else { throw LiteRTLLMError.modelMissing }
        let size = try modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 6_000_000_000 else { throw LiteRTLLMError.modelMissing }
        #if canImport(LiteRTLM)
        guard let engine else { throw LiteRTLLMError.runtimeUnavailable }
        let started = ContinuousClock.now
        var firstResponse: Duration?
        var response = ""
        await memorySampler.start()
        // Each lesson starts with a clean context; dropping the prior session releases its KV cache.
        conversation = nil
        let configuration = ConversationConfig(
            systemMessage: Message("You create original English lessons for Japanese learners. Return only the requested JSON object.", role: .system),
            samplerConfig: try SamplerConfig(topK: 40, topP: 0.9, temperature: 0.2),
            thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0),
            enableResponseFormat: false
        )
        let active = try await engine.createConversation(with: configuration)
        conversation = active
        do {
            for try await chunk in active.sendMessageStream(Message(prompt), maxOutputTokens: 512,
                                                            thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0)) {
                try Task.checkCancellation()
                let text = chunk.toString
                if !text.isEmpty, firstResponse == nil { firstResponse = started.duration(to: .now) }
                response += text
            }
        } catch {
            conversation = nil
            let decodeTokensPerSecond = try? active.getBenchmarkInfo().lastDecodeTokensPerSecond
            let peak = await memorySampler.stop()
            saveMetrics(loadSeconds: loadSeconds, first: firstResponse, started: started,
                        characters: response.count, decodeTokensPerSecond: decodeTokensPerSecond, peak: peak)
            throw error
        }
        let decodeTokensPerSecond = try? active.getBenchmarkInfo().lastDecodeTokensPerSecond
        conversation = nil
        let peak = await memorySampler.stop()
        saveMetrics(loadSeconds: loadSeconds, first: firstResponse, started: started,
                    characters: response.count, decodeTokensPerSecond: decodeTokensPerSecond, peak: peak)
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ContentError.invalidJSON }
        return response
        #else
        throw LiteRTLLMError.runtimeUnavailable
        #endif
    }

    public func cancel() async {
        #if canImport(LiteRTLM)
        try? conversation?.cancel()
        #endif
    }

    public func unload() async {
        #if canImport(LiteRTLM)
        if let conversation { try? conversation.cancel() }
        conversation = nil
        engine = nil
        #endif
        modelURL = nil
        loadSeconds = nil
        let unloadedID = trackedModelID
        trackedModelID = nil
        if let unloadedID { await ModelRuntimeCoordinator.shared.didUnload(unloadedID) }
    }

    public func inferenceMetrics() async -> LLMInferenceMetrics? { latestMetrics }

    #if canImport(LiteRTLM)
    private func saveMetrics(loadSeconds: Double?, first: Duration?, started: ContinuousClock.Instant,
                             characters: Int, decodeTokensPerSecond: Double?, peak: UInt64?) {
        latestMetrics = LLMInferenceMetrics(
            modelLoadSeconds: loadSeconds,
            timeToFirstResponseSeconds: first?.seconds,
            generationSeconds: started.duration(to: .now).seconds,
            outputCharacters: characters,
            decodeTokensPerSecond: decodeTokensPerSecond.flatMap { $0.isFinite && $0 > 0 ? $0 : nil },
            peakProcessMemoryBytes: peak
        )
    }
    #endif
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
