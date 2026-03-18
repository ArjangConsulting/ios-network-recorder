import APITraceCore

/// Installs a release-safe no-op backend.
public enum APITraceNoopBootstrap {
    public static func install() {
        APITrace.install(APITraceNoopBackend())
    }
}
