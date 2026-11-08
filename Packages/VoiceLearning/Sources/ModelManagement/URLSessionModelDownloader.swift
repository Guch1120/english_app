import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads a model file directly to disk and reports transfer progress without buffering it in memory.
public enum URLSessionModelDownloader {
    public static func download(
        from remoteURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        let reporter = ByteProgressReporter(progress: progress)
        let operation = FileDownloadOperation(destination: destination, progress: reporter)
        try await operation.run(from: remoteURL)
    }
}

private actor ByteProgressReporter {
    private let progress: @Sendable (Int64) async -> Void
    private var lastReportedBytes: Int64 = 0

    init(progress: @escaping @Sendable (Int64) async -> Void) {
        self.progress = progress
    }

    func report(_ bytes: Int64) async {
        let next = max(lastReportedBytes, max(0, bytes))
        guard next > lastReportedBytes else { return }
        lastReportedBytes = next
        await progress(next)
    }
}

private final class FileDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: ByteProgressReporter
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var transferError: Error?
    private var cancelled = false
    private var lastReportedBytes: Int64 = 0

    init(destination: URL, progress: ByteProgressReporter) {
        self.destination = destination
        self.progress = progress
    }

    func run(from remoteURL: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegateQueue = OperationQueue()
                delegateQueue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
                let task = session.downloadTask(with: remoteURL)
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

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let threshold = totalBytesExpectedToWrite > 0
            ? max(Int64(512 * 1024), totalBytesExpectedToWrite / 100)
            : Int64(512 * 1024)
        let shouldReport = lock.withLock { () -> Bool in
            guard totalBytesWritten == totalBytesExpectedToWrite || totalBytesWritten - lastReportedBytes >= threshold else {
                return false
            }
            lastReportedBytes = totalBytesWritten
            return true
        }
        if shouldReport {
            let received = max(0, totalBytesWritten)
            Task { await progress.report(received) }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let received = max(0, downloadTask.countOfBytesReceived)
            let shouldReport = lock.withLock { () -> Bool in
                guard received > lastReportedBytes else { return false }
                lastReportedBytes = received
                return true
            }
            if shouldReport {
                Task { await progress.report(received) }
            }
        } catch {
            lock.withLock { transferError = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let completion = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
            let continuation = self.continuation
            self.continuation = nil
            let resultError = error ?? transferError
            self.task = nil
            self.session = nil
            return (continuation, resultError)
        }
        session.finishTasksAndInvalidate()
        guard let continuation = completion.0 else { return }
        if let error = completion.1 {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func cancel() {
        let task = lock.withLock { () -> URLSessionDownloadTask? in
            cancelled = true
            return self.task
        }
        task?.cancel()
    }
}
