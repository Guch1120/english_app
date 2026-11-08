import Foundation

public struct TTSCacheKey: Codable, Sendable, Equatable {
    public let text: String
    public let engine: String
    public let modelRevision: String
    public let voice: String
    public let parameters: [String: String]
    public init(text: String, engine: String, modelRevision: String, voice: String, parameters: [String: String] = [:]) {
        self.text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ").precomposedStringWithCanonicalMapping
        self.engine = engine; self.modelRevision = modelRevision; self.voice = voice; self.parameters = parameters
    }
}
public enum AudioFileError: Error { case invalidWAV, invalidCacheLimit }
public struct WAVInfo: Sendable, Equatable {
    public let sampleRate: Double
    public let duration: Double
    public init(data: Data) throws {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset+1]) << 8 }
        func u32(_ offset: Int) -> Int { (0..<4).reduce(0) { $0 | Int(bytes[offset+$1]) << (8*$1) } }
        guard bytes.count >= 44, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else { throw AudioFileError.invalidWAV }
        var offset = 12, rate = 0, byteRate = 0, audioBytes: Int?
        while offset + 8 <= bytes.count {
            let tag = String(bytes: bytes[offset..<offset+4], encoding: .ascii)
            let length = u32(offset+4), start = offset+8
            guard length <= bytes.count-start else { throw AudioFileError.invalidWAV }
            if tag == "fmt " {
                guard length >= 16, [1,3].contains(u16(start)), (1...2).contains(u16(start+2)) else { throw AudioFileError.invalidWAV }
                rate = u32(start+4); byteRate = u32(start+8)
            }
            if tag == "data" { audioBytes = length }
            offset = start + length + (length % 2)
        }
        guard rate > 0, byteRate > 0, let audioBytes, audioBytes > 0 else { throw AudioFileError.invalidWAV }
        self.sampleRate = Double(rate); self.duration = Double(audioBytes) / Double(byteRate)
    }
}

/// Sidecars use UUID names and exact key equality, avoiding hash collisions and path-derived text.
public actor TTSAudioCache {
    private struct Entry: Codable {
        let id: UUID
        let key: TTSCacheKey
        var accessed: Date
    }
    private let directory: URL
    private var maximumBytes: Int
    public init(directory: URL, maximumBytes: Int = 128 * 1024 * 1024) throws {
        guard maximumBytes > 0 else { throw AudioFileError.invalidCacheLimit }
        self.directory = directory; self.maximumBytes = maximumBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func entries() throws -> [Entry] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var records: [Entry] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data),
               url.deletingPathExtension().lastPathComponent == entry.id.uuidString,
               FileManager.default.fileExists(atPath: file(entry.id,"wav").path) {
                records.append(entry)
            } else { try? FileManager.default.removeItem(at: url) }
        }
        let ids = Set(records.map { $0.id.uuidString })
        for url in urls where url.pathExtension == "wav" && !ids.contains(url.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
        return records
    }
    private func file(_ id: UUID, _ ext: String) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension(ext) }
    private func write(_ entry: Entry) throws { try JSONEncoder().encode(entry).write(to: file(entry.id,"json"), options: .atomic) }
    public func lookup(_ key: TTSCacheKey) throws -> AudioAsset? {
        guard var entry = try entries().first(where: { $0.key == key }) else { return nil }
        let url = file(entry.id,"wav")
        guard let data = try? Data(contentsOf: url), let info = try? WAVInfo(data: data) else {
            try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: file(entry.id,"json")); return nil
        }
        entry.accessed = Date(); try write(entry)
        return AudioAsset(url: url, duration: info.duration, sampleRate: info.sampleRate)
    }
    public func store(_ data: Data, key: TTSCacheKey) throws -> AudioAsset {
        let info = try WAVInfo(data: data)
        guard data.count <= maximumBytes else { throw AudioFileError.invalidCacheLimit }
        let entry = Entry(id: UUID(), key: key, accessed: Date())
        guard data.count + (try JSONEncoder().encode(entry)).count <= maximumBytes else { throw AudioFileError.invalidCacheLimit }
        try data.write(to: file(entry.id,"wav"), options: .atomic)
        do { try write(entry); try trim(protecting: entry.id) }
        catch { try? FileManager.default.removeItem(at: file(entry.id,"wav")); try? FileManager.default.removeItem(at: file(entry.id,"json")); throw error }
        return AudioAsset(url: file(entry.id,"wav"), duration: info.duration, sampleRate: info.sampleRate)
    }
    public func sizeBytes() throws -> Int {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .reduce(0) { $0 + ((try $1.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) }
    }
    public func setLimit(_ bytes: Int) throws { guard bytes > 0 else { throw AudioFileError.invalidCacheLimit }; maximumBytes = bytes; try trim() }
    private func trim(protecting: UUID? = nil) throws {
        let records = try entries()
        var size = try sizeBytes()
        for entry in records.sorted(by: { $0.accessed < $1.accessed }) where entry.id != protecting && size > maximumBytes {
            for ext in ["wav","json"] {
                let url = file(entry.id,ext)
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                try? FileManager.default.removeItem(at: url); size -= bytes
            }
        }
    }
    public func clear() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
public enum TTSMeasurementError: Error { case noteTooLong }
public struct TTSMeasurement: Codable, Identifiable, Sendable {
    public let id: UUID
    public let engine: String
    public let voice: String
    public let modelRevision: String
    public let generatedAt: Date
    public let generationSeconds: Double?
    public let duration: Double
    public let sampleRate: Double
    public let cacheHit: Bool
    public let comparisonID: UUID?
    public let peakProcessRSS: UInt64?
    /// User content, stored locally with the measurement; never diagnostic output.
    public private(set) var listeningNote: String?
    public mutating func setListeningNote(_ note: String) throws {
        guard note.count <= 2000 else { throw TTSMeasurementError.noteTooLong }
        listeningNote = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
    }
    public var realTimeFactor: Double? { generationSeconds.map { $0 / duration } }
    public init(engine: String, voice: String, modelRevision: String, generationSeconds: Double?, asset: AudioAsset, cacheHit: Bool, comparisonID: UUID? = nil, peakProcessRSS: UInt64? = nil) {
        self.id = UUID(); self.engine = engine; self.voice = voice; self.modelRevision = modelRevision; self.generatedAt = Date()
        self.generationSeconds = generationSeconds; self.duration = asset.duration; self.sampleRate = asset.sampleRate; self.cacheHit = cacheHit; self.comparisonID = comparisonID; self.peakProcessRSS = peakProcessRSS
        self.listeningNote = nil
    }
}
