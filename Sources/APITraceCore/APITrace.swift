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
        try jsonData(for: records(), prettyPrinted: prettyPrinted)
    }

    static func jsonData(for records: [APITraceRecord], prettyPrinted: Bool = true) throws -> Data {
        try makeExportEncoder(prettyPrinted: prettyPrinted).encode(records)
    }

    /// Exports captured records as a HAR 1.2 archive.
    public static func exportHAR(prettyPrinted: Bool = true) throws -> Data {
        try harData(for: records(), prettyPrinted: prettyPrinted)
    }

    static func harData(for records: [APITraceRecord], prettyPrinted: Bool = true) throws -> Data {
        let export = HARExport(
            log: HARLog(
                version: "1.2",
                creator: HARCreator(name: "APITrace", version: "1.0"),
                entries: records.map(HAREntry.init)
            )
        )
        return try makeExportEncoder(prettyPrinted: prettyPrinted).encode(export)
    }

    // Millisecond-precision ISO 8601; the same wire format the Android SDK exports.
    private static let iso8601MillisecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeExportEncoder(prettyPrinted: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601MillisecondsFormatter.string(from: date))
        }
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
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
