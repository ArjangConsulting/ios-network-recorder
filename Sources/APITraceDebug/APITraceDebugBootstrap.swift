import APITraceCore

/// Installs the URLSession-backed debug capture backend.
public enum APITraceDebugBootstrap {
    public static func install(maxRecords: Int = 500, redactor: APITraceRedactor = .default) {
        APITrace.install(APITraceURLSessionBackend(maxRecords: maxRecords, redactor: redactor))
    }
}
