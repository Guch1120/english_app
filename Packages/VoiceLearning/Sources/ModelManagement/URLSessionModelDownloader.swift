import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Validates a server's response to a byte-range request and returns the first byte written.
struct ModelDownloadResponsePlan {
    static func firstByte(
        statusCode: Int,
        contentRange: String?,
        requestedOffset: Int64,
        expectedSize: Int64
    ) throws -> Int64 {
        if statusCode == 200 { return 0 } // The server ignored Range; replace the stale partial.
        guard statusCode == 206, let contentRange else {
            if statusCode == 416, requestedOffset > 0 { throw ResumeRangeRejected() }
            throw URLError(.badServerResponse)
        }

        let components = contentRange.split(separator: " ", maxSplits: 1)
        let rangeAndSize = components.count == 2 ? components[1].split(separator: "/", maxSplits: 1) : []
        let byteRange = rangeAndSize.first?.split(separator: "-", maxSplits: 1) ?? []
        guard components.first == "bytes", rangeAndSize.count == 2, byteRange.count == 2,
              let start = Int64(byteRange[0]), let end = Int64(byteRange[1]),
              let total = Int64(rangeAndSize[1]), start == requestedOffset,
              end >= start, end < total, total == expectedSize else {
            throw ResumeRangeRejected()
        }
        return start
    }
}

private struct ResumeRangeRejected: Error {}

/// Downloads directly into a persistent partial file, reports byte progress, and resumes with HTTP Range.
public enum URLSessionModelDownloader {
    public static func download(
        from remoteURL: URL,
        to destination: URL,
        expectedSize: Int64,
        progress: any ModelDownloadProgress
    ) async throws {
        try await download(from: remoteURL, to: destination, expectedSize: expectedSize, progress: progress, sessionConfiguration: .default)
    }

    static func download(
        from remoteURL: URL,
        to destination: URL,
        expectedSize: Int64,
        progress: any ModelDownloadProgress,
        sessionConfiguration: URLSessionConfiguration
    ) async throws {
        guard expectedSize > 0 else { throw URLError(.badURL) }
        let existingSize = ((try? FileManager.default.attributesOfItem(atPath: destination.path)[.size]) as? Int).map(Int64.init) ?? 0
        if existingSize >= expectedSize {
            try FileManager.default.removeItem(at: destination)
        }

        let reporter = ByteProgressReporter(progress: progress)
        let offset = existingSize < expectedSize ? existingSize : 0
        do {
            try await FileDownloadOperation(
                destination: destination, expectedSize: expectedSize, initialOffset: offset,
                progress: reporter, sessionConfiguration: sessionConfiguration
            ).run(from: remoteURL)
        } catch is ResumeRangeRejected where offset > 0 {
            // Some mirrors do not honor Range or return stale range metadata. Restart once from byte zero.
            try? FileManager.default.removeItem(at: destination)
            try await FileDownloadOperation(
                destination: destination, expectedSize: expectedSize, initialOffset: 0,
                progress: reporter, sessionConfiguration: sessionConfiguration
            ).run(from: remoteURL)
        }
        await reporter.finish()
    }
}

private actor ByteProgressReporter: ModelDownloadProgress {
    private let progress: any ModelDownloadProgress
    private var lastReportedBytes: Int64 = 0
    private var finished = false

    init(progress: any ModelDownloadProgress) {
        self.progress = progress
    }

    func report(bytesReceived bytes: Int64) async {
        guard !finished else { return }
        let next = max(lastReportedBytes, max(0, bytes))
        guard next > lastReportedBytes else { return }
        lastReportedBytes = next
        await progress.report(bytesReceived: next)
    }

    func finish() { finished = true }
}

private final class FileDownloadOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSize: Int64
    private let initialOffset: Int64
    private let progress: ByteProgressReporter
    private let sessionConfiguration: URLSessionConfiguration
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var transferError: Error?
    private var cancelled = false
    private var fileHandle: FileHandle?
    private var receivedBytes: Int64
    private var lastReportedBytes: Int64

    init(
        destination: URL,
        expectedSize: Int64,
        initialOffset: Int64,
        progress: ByteProgressReporter,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.initialOffset = initialOffset
        self.progress = progress
        self.sessionConfiguration = sessionConfiguration
        self.receivedBytes = initialOffset
        self.lastReportedBytes = initialOffset
    }

    func run(from remoteURL: URL) async throws {
        try preparePartialFile()
        await progress.report(bytesReceived: initialOffset)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegateQueue = OperationQueue()
                delegateQueue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: delegateQueue)
                var request = URLRequest(url: remoteURL)
                if initialOffset > 0 { request.setValue("bytes=\(initialOffset)-", forHTTPHeaderField: "Range") }
                let task = session.dataTask(with: request)
                let shouldCancel = lock.withLock {
                    self.continuation = continuation
                    self.session = session
                    self.task = task
                    return cancelled
                }
                if shouldCancel { task.cancel() } else { task.resume() }
            }
        } onCancel: {
            cancel()
        }
    }

    private func preparePartialFile() throws {
        if !FileManager.default.fileExists(atPath: destination.path) {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forUpdating: destination)
        try handle.seekToEnd()
        fileHandle = handle
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let firstByte = try ModelDownloadResponsePlan.firstByte(
                statusCode: response.statusCode,
                contentRange: response.value(forHTTPHeaderField: "Content-Range"),
                requestedOffset: initialOffset,
                expectedSize: expectedSize
            )
            guard let handle = fileHandle else { throw CocoaError(.fileWriteUnknown) }
            if firstByte == 0 {
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
            } else {
                try handle.seekToEnd()
            }
            receivedBytes = firstByte
            if lastReportedBytes > firstByte { lastReportedBytes = firstByte }
            completionHandler(.allow)
        } catch {
            transferError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard transferError == nil, let handle = fileHandle else { return }
        let nextBytes = receivedBytes + Int64(data.count)
        guard nextBytes <= expectedSize else {
            transferError = URLError(.dataLengthExceedsMaximum)
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
            receivedBytes = nextBytes
            let threshold = max(Int64(512 * 1024), expectedSize / 100)
            if receivedBytes == expectedSize || receivedBytes - lastReportedBytes >= threshold {
                lastReportedBytes = receivedBytes
                let value = receivedBytes
                Task { await progress.report(bytesReceived: value) }
            }
        } catch {
            transferError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let completion = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
            let continuation = self.continuation
            self.continuation = nil
            let resultError = transferError ?? error
            self.task = nil
            self.session = nil
            return (continuation, resultError)
        }
        try? fileHandle?.close()
        fileHandle = nil
        session.finishTasksAndInvalidate()
        guard let continuation = completion.0 else { return }
        if let error = completion.1 {
            continuation.resume(throwing: error)
        } else if receivedBytes != expectedSize {
            continuation.resume(throwing: ModelInstallError.incompleteDownload)
        } else {
            continuation.resume()
        }
    }

    private func cancel() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            cancelled = true
            return self.task
        }
        task?.cancel()
    }
}
