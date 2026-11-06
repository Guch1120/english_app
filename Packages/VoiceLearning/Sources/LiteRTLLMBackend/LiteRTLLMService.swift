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
    private var loadSeconds: Double?
    private var latestMetrics: LLMInferenceMetrics?
    private let memorySampler = ProcessMemorySampler()
    #if canImport(LiteRTLM)
    private var engine: Engine?
    private var conversation: Conversation?
    #endif

    public init() {}

    public func load(modelURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw LiteRTLLMError.modelMissing }
        guard self.modelURL != modelURL else { return }
        await unload()
        let started = ContinuousClock.now
        #if canImport(LiteRTLM)
        let config = try EngineConfig(modelPath: modelURL.path, backend: .gpu, maxNumTokens: 2048)
        let loaded = Engine(engineConfig: config)
        try await loaded.initialize()
        engine = loaded
        self.modelURL = modelURL
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
            let peak = await memorySampler.stop()
            saveMetrics(loadSeconds: loadSeconds, first: firstResponse, started: started,
                        characters: response.count, peak: peak)
            throw error
        }
        conversation = nil
        let peak = await memorySampler.stop()
        saveMetrics(loadSeconds: loadSeconds, first: firstResponse, started: started,
                    characters: response.count, peak: peak)
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
    }

    public func inferenceMetrics() async -> LLMInferenceMetrics? { latestMetrics }

    #if canImport(LiteRTLM)
    private func saveMetrics(loadSeconds: Double?, first: Duration?, started: ContinuousClock.Instant,
                             characters: Int, peak: UInt64?) {
        latestMetrics = LLMInferenceMetrics(
            modelLoadSeconds: loadSeconds,
            timeToFirstResponseSeconds: first?.seconds,
            generationSeconds: started.duration(to: .now).seconds,
            outputCharacters: characters,
            peakProcessMemoryBytes: peak
        )
    }
    #endif
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
