import APITraceCore
import Foundation

/// URLSession backend that captures HTTP/HTTPS exchanges via URLProtocol.
public final class APITraceURLSessionBackend: APITraceBackend {
    private let recorder: APITraceRecorder
    private let redactor: APITraceRedactor
    private let lock = NSLock()
    private var started = false

    public init(maxRecords: Int = 500, redactor: APITraceRedactor = .default) {
        self.recorder = APITraceRecorder(maxRecords: maxRecords)
        self.redactor = redactor
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !started else { return }

        APITraceURLProtocolContext.configure(recorder: recorder, redactor: redactor)
        URLProtocol.registerClass(APITraceURLProtocol.self)
        started = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard started else { return }

        URLProtocol.unregisterClass(APITraceURLProtocol.self)
        started = false
    }

    public func clear() {
        recorder.clear()
    }

    public func records() -> [APITraceRecord] {
        recorder.snapshot()
    }
}
