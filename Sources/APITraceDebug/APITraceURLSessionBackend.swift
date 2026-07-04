import APITraceCore
import Foundation

/// URLSession backend that captures HTTP/HTTPS exchanges via URLProtocol.
public final class APITraceURLSessionBackend: APITraceBackend {
    private let recorder: APITraceRecorder
    private let redactor: APITraceRedactor
    private let maxBodyBytes: Int
    private let lock = NSLock()
    private var started = false

    public init(maxRecords: Int = 500, redactor: APITraceRedactor = .default, maxBodyBytes: Int = 64 * 1024) {
        self.recorder = APITraceRecorder(maxRecords: maxRecords)
        self.redactor = redactor
        self.maxBodyBytes = maxBodyBytes
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !started else { return }

        APITraceURLProtocolContext.configure(recorder: recorder, redactor: redactor, maxBodyBytes: maxBodyBytes)
        APITraceURLProtocolContext.setCapturing(true)
        URLProtocol.registerClass(APITraceURLProtocol.self)
        started = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        guard started else { return }

        // Flip the capture flag first so canInit() rejects new requests immediately,
        // independent of any URLProtocol registration timing.
        APITraceURLProtocolContext.setCapturing(false)
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
