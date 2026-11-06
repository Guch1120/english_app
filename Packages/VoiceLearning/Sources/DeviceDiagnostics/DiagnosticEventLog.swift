import Foundation

public enum DiagnosticSubsystem: String, Codable, Sendable {
    case app
    case tts
    case asr
    case llm
    case reuse
}

public enum DiagnosticAction: String, Codable, Sendable {
    case appLaunch
    case modelDownload
    case modelLoad
    case modelUnload
    case inference
    case recording
    case transcription
    case enhancement
    case audioInterruption
    case memoryWarning
}

public enum DiagnosticOutcome: String, Codable, Sendable {
    case started
    case succeeded
    case failed
    case cancelled
    case observed
}

public enum DiagnosticModel: String, Codable, Sendable {
    case kokoro
    case pocket
    case parakeet
    case appleSpeech
    case gemmaE2B
    case reuse
    case system
}

public enum DiagnosticThermalState: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unavailable

    public static var current: Self {
        #if canImport(Darwin)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unavailable
        }
        #else
        .unavailable
        #endif
    }
}

public struct DiagnosticEvent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let subsystem: DiagnosticSubsystem
    public let action: DiagnosticAction
    public let model: DiagnosticModel
    public let outcome: DiagnosticOutcome
    public let elapsedMilliseconds: Int?
    public let modelBytes: UInt64?
    public let peakMemoryBytes: UInt64?
    public let cacheBytes: UInt64?
    public let thermalState: DiagnosticThermalState

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        subsystem: DiagnosticSubsystem,
        action: DiagnosticAction,
        model: DiagnosticModel,
        outcome: DiagnosticOutcome,
        elapsedMilliseconds: Int? = nil,
        modelBytes: UInt64? = nil,
        peakMemoryBytes: UInt64? = nil,
        cacheBytes: UInt64? = nil,
        thermalState: DiagnosticThermalState = .unavailable
    ) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.action = action
        self.model = model
        self.outcome = outcome
        self.elapsedMilliseconds = elapsedMilliseconds.map { max(0, $0) }
        self.modelBytes = modelBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.cacheBytes = cacheBytes
        self.thermalState = thermalState
    }
}

/// A bounded, on-device event log. Its API accepts only fixed enums and numeric metrics,
/// so callers cannot accidentally store audio, transcripts, prompts, or localized errors.
public actor DiagnosticEventLog {
    public static let shared = DiagnosticEventLog(
        fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics.json"),
        maximumEvents: 500
    )

    private let fileURL: URL
    private let maximumEvents: Int
    private var events: [DiagnosticEvent]?

    public init(fileURL: URL, maximumEvents: Int = 500) {
        self.fileURL = fileURL
        self.maximumEvents = max(1, maximumEvents)
    }

    public func record(_ event: DiagnosticEvent) {
        var current = loadIfNeeded()
        current.append(event)
        if current.count > maximumEvents { current.removeFirst(current.count - maximumEvents) }
        events = current
        persist(current)
    }

    public func recentEvents(limit: Int = 100) -> [DiagnosticEvent] {
        let current = loadIfNeeded()
        return Array(current.suffix(max(0, limit)).reversed())
    }

    public func clear() {
        events = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func loadIfNeeded() -> [DiagnosticEvent] {
        if let events { return events }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            events = []
            return []
        }
        let bounded = Array(decoded.suffix(maximumEvents))
        events = bounded
        return bounded
    }

    private func persist(_ events: [DiagnosticEvent]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = fileURL
            try protectedURL.setResourceValues(values)
        } catch {
            // Diagnostics must never interrupt a learning operation.
        }
    }
}
