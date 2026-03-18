import Foundation

/// Facade for installing, controlling, and exporting network trace history.
public enum APITrace {
    private static let state = APITraceState()

    /// Installs a backend implementation. Typically called once at app startup.
    public static func install(_ backend: APITraceBackend) {
        state.install(backend)
    }

    /// Enables capture for the installed backend.
    public static func start() {
        state.backend.start()
    }

    /// Disables capture for the installed backend.
    public static func stop() {
        state.backend.stop()
    }

    /// Clears in-memory trace history.
    public static func clear() {
        state.backend.clear()
    }

    /// Returns all captured network exchange records.
    public static func records() -> [APITraceRecord] {
        state.backend.records()
    }

    /// Exports captured records as JSON.
    public static func exportJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(records())
    }
}

private final class APITraceState {
    private let lock = NSLock()
    private var currentBackend: APITraceBackend = APITraceNoopBackend()

    var backend: APITraceBackend {
        lock.lock()
        defer { lock.unlock() }
        return currentBackend
    }

    func install(_ backend: APITraceBackend) {
        lock.lock()
        defer { lock.unlock() }

        currentBackend.stop()
        currentBackend = backend
    }
}
