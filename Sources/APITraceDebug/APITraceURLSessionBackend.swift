import APITraceCore
import Foundation

/// URLSession backend that captures HTTP/HTTPS exchanges via URLProtocol.
public final class APITraceURLSessionBackend: APITraceBackend {
    private let recorder: APITraceRecorder
    private let redactor: APITraceRedactor
    private let maxBodyBytes: Int
    private let captureRequestBodies: Bool
    private let captureResponseBodies: Bool
    private let lock = NSLock()
    private var started = false

    public init(
        maxRecords: Int = 500,
        redactor: APITraceRedactor = .default,
        maxBodyBytes: Int = 64 * 1024,
        captureRequestBodies: Bool = true,
        captureResponseBodies: Bool = true
    ) {
        self.recorder = APITraceRecorder(maxRecords: maxRecords)
        self.redactor = redactor
        self.maxBodyBytes = maxBodyBytes
        self.captureRequestBodies = captureRequestBodies
        self.captureResponseBodies = captureResponseBodies
    }

    /// Adds the capture protocol to a custom session configuration. `URLProtocol.registerClass`
    /// only reaches `URLSession.shared`; sessions built from their own configuration must be
    /// opted in with this before the `URLSession` is created. Capture still only happens
    /// between `start()` and `stop()`.
    public static func enableCapture(in configuration: URLSessionConfiguration) {
        let existing = configuration.protocolClasses ?? []
        guard !existing.contains(where: { $0 == APITraceURLProtocol.self }) else { return }
        configuration.protocolClasses = [APITraceURLProtocol.self] + existing
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }

        guard !started else { return }

        APITraceURLProtocolContext.configure(
            recorder: recorder,
            redactor: redactor,
            maxBodyBytes: maxBodyBytes,
            captureRequestBodies: captureRequestBodies,
            captureResponseBodies: captureResponseBodies
        )
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
