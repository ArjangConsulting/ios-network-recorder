import APITraceCore

/// Installs the URLSession-backed debug capture backend.
public enum APITraceDebugBootstrap {
    public static func install(
        maxRecords: Int = 500,
        redactor: APITraceRedactor = .default,
        maxBodyBytes: Int = 64 * 1024
    ) {
        APITrace.install(
            APITraceURLSessionBackend(maxRecords: maxRecords, redactor: redactor, maxBodyBytes: maxBodyBytes)
        )
    }
}
