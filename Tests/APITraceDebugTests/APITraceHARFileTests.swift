@testable import APITraceCore
@testable import APITraceDebug
import Foundation
import Testing

@Suite("APITraceHARFile")
struct APITraceHARFileTests {
    @Test("The launch environment turns HAR file export on", arguments: ["1", "true", "YES"])
    func requested(value: String) {
        #expect(APITraceHARFile.url(environment: ["APITRACE_HAR_FILE": value]) == APITraceHARFile.defaultURL)
    }

    @Test("Without the key, or with another value, no file is requested", arguments: [[:], ["APITRACE_HAR_FILE": "0"], ["APITRACE_HAR_FILE": ""]])
    func notRequested(environment: [String: String]) {
        #expect(APITraceHARFile.url(environment: environment) == nil)
    }

    @Test("The default file sits in the app's temporary directory")
    func defaultLocation() {
        #expect(APITraceHARFile.defaultURL.deletingLastPathComponent().standardizedFileURL
            == FileManager.default.temporaryDirectory.standardizedFileURL)
        #expect(APITraceHARFile.defaultURL.lastPathComponent == "apitrace.har")
    }
}

/// Capture goes through process-global URLProtocol state, so this joins the serialized
/// lifecycle suite instead of running beside it.
extension APITraceURLSessionBackendTests {
    @Test("A captured exchange is written to the HAR file, and clear() empties it")
    func capturedExchangeIsWrittenToHARFile() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apitrace-test-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("trace.har")
        defer { try? FileManager.default.removeItem(at: directory) }

        let backend = APITraceURLSessionBackend(harFileURL: url)
        defer { backend.stop() }
        backend.start()

        let config = URLSessionConfiguration.default
        APITraceDebugBootstrap.enableCapture(in: config)
        _ = try await URLSession(configuration: config)
            .data(for: URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ping")!))
        backend.flushHARFile()

        #expect(backend.records().count == 1)
        let entries = try Self.harEntries(at: url)
        #expect(entries.count == 1)
        #expect((entries.first?["request"] as? [String: Any])?["url"] as? String == "http://127.0.0.1:\(port)/ping")

        backend.clear()
        backend.flushHARFile()
        #expect(try Self.harEntries(at: url).isEmpty)
    }

    private static func harEntries(at url: URL) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let log = try #require(object?["log"] as? [String: Any])
        #expect(log["version"] as? String == "1.2")
        return try #require(log["entries"] as? [[String: Any]])
    }
}
