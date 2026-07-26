import APITraceCore
import Foundation

enum APITraceURLProtocolContext {
    static let handledKey = "com.apitrace.handled"

    /// Snapshot of the active capture configuration, read atomically by in-flight requests.
    struct Configuration {
        let recorder: APITraceRecorder
        let redactor: APITraceRedactor
        let maxBodyBytes: Int
        let captureRequestBodies: Bool
        let captureResponseBodies: Bool
    }

    struct Snapshot {
        let configuration: Configuration
        let isCapturing: Bool
    }

    private static let lock = NSLock()
    private static var current = Configuration(
        recorder: APITraceRecorder(maxRecords: 500),
        redactor: .default,
        maxBodyBytes: 64 * 1024,
        captureRequestBodies: false,
        captureResponseBodies: false
    )
    private static var isCapturing = false

    static func configure(
        recorder: APITraceRecorder,
        redactor: APITraceRedactor,
        maxBodyBytes: Int,
        captureRequestBodies: Bool,
        captureResponseBodies: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }
        current = Configuration(
            recorder: recorder,
            redactor: redactor,
            maxBodyBytes: maxBodyBytes,
            captureRequestBodies: captureRequestBodies,
            captureResponseBodies: captureResponseBodies
        )
    }

    /// Toggles whether `APITraceURLProtocol` should intercept requests. This is the
    /// authoritative on/off switch, independent of `URLProtocol.registerClass`/`unregisterClass`
    /// timing, so `start()`/`stop()` take effect immediately and deterministically.
    static func setCapturing(_ capturing: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isCapturing = capturing
    }

    /// Thread-safe snapshot of the current configuration and capture state. `APITraceURLProtocol`
    /// runs on arbitrary background threads, so reads must not race with `configure`/`setCapturing`.
    static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(configuration: current, isCapturing: isCapturing)
    }
}
