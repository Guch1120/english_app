import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Sampled process RSS, not a per-model allocation count or a guaranteed instantaneous peak.
public actor ProcessMemorySampler {
    private var maximum: UInt64?
    private var task: Task<Void, Never>?
    public init() {}
    public nonisolated static func currentResidentBytes() -> UInt64? { residentBytes() }
    deinit { task?.cancel() }
    public func start() {
        task?.cancel(); maximum = Self.residentBytes()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 50_000_000) } catch { break }
                await self?.observe()
            }
        }
    }
    private func observe() {
        if let bytes = Self.residentBytes() { maximum = max(maximum ?? 0, bytes) }
    }
    public func stop() -> UInt64? { task?.cancel(); task = nil; observe(); return maximum }
    private nonisolated static func residentBytes() -> UInt64? {
        #if canImport(Darwin)
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
        #else
        return nil
        #endif
    }
}
