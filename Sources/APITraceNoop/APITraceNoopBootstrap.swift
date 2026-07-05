import APITraceCore
import Foundation

/// Installs a release-safe no-op backend.
public enum APITraceNoopBootstrap {
    public static func install() {
        APITrace.install(APITraceNoopBackend())
    }

    /// No-op counterpart of `APITraceDebugBootstrap.enableCapture(in:)` so call sites
    /// don't need conditional compilation around session construction.
    public static func enableCapture(in configuration: URLSessionConfiguration) {}
}
