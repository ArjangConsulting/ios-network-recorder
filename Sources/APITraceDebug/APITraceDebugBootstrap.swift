import APITraceCore
import Foundation

/// Installs the URLSession-backed debug capture backend.
///
/// By default the history is also written to ``APITraceHARFile/defaultURL`` when the app is
/// launched with `APITRACE_HAR_FILE=1` in its environment, and to no file otherwise.
public enum APITraceDebugBootstrap {
    public static func install(
        maxRecords: Int = 500,
        redactor: APITraceRedactor = .default,
        maxBodyBytes: Int = 64 * 1024,
        captureRequestBodies: Bool = false,
        captureResponseBodies: Bool = false,
        harFileURL: URL? = APITraceHARFile.url()
    ) {
        APITrace.install(
            APITraceURLSessionBackend(
                maxRecords: maxRecords,
                redactor: redactor,
                maxBodyBytes: maxBodyBytes,
                captureRequestBodies: captureRequestBodies,
                captureResponseBodies: captureResponseBodies,
                harFileURL: harFileURL
            )
        )
    }

    /// Opts a custom `URLSessionConfiguration` into capture. Global registration only
    /// reaches `URLSession.shared`; call this before creating any custom session whose
    /// traffic should be traced.
    public static func enableCapture(in configuration: URLSessionConfiguration) {
        APITraceURLSessionBackend.enableCapture(in: configuration)
    }
}
