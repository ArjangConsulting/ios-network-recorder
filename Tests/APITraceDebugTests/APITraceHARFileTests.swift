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
    @Test("Automatic HAR writes contain only sanitized capture")
    func harFileExcludesCredentials() async throws {
        let secret = "example-secret-8297"
        let json = #"{"items":[{"password":"\#(secret)","author":"pilot","note":"eyJhbGci.eyJzdWIi.\#(secret)"}]}"#
        let server = LoopbackHTTPServer(routes: [
            "/exchange": .init(headers: [
                "Content-Type: application/json",
                "Set-Cookie: first=\(secret); Expires=Wed, 21 Oct 2030 07:28:00 GMT, second=\(secret); HttpOnly",
                "X-Goog-Api-Key: \(secret)",
                "Content-Location: /next?state=\(secret)",
            ], body: json),
        ])
        let port = try server.start()
        defer { server.stop() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let har = directory.appendingPathComponent("trace.har")
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = APITraceURLSessionBackend(captureRequestBodies: true, captureResponseBodies: true, harFileURL: har)
        backend.start()
        defer { backend.stop() }

        let config = URLSessionConfiguration.ephemeral
        APITraceDebugBootstrap.enableCapture(in: config)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/exchange?API_KEY=\(secret)&keyword=telescope"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("client_secret=\(secret)&author=pilot".utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("first=\(secret); second=\(secret)", forHTTPHeaderField: "Cookie")
        request.setValue("session-42", forHTTPHeaderField: "X-Session-Ref")
        let (data, _) = try await URLSession(configuration: config).data(for: request)
        #expect(String(decoding: data, as: UTF8.self) == json)
        backend.flushHARFile()

        let record = try #require(backend.records().first)
        #expect(!String(decoding: try JSONEncoder().encode(record), as: UTF8.self).contains(secret))
        #expect(!String(decoding: try Data(contentsOf: har), as: UTF8.self).contains(secret))
        let entries = try Self.harEntries(at: har)
        let entry = try #require(entries.first)
        let capturedRequest = try #require(entry["request"] as? [String: Any])
        let capturedResponse = try #require(entry["response"] as? [String: Any])
        #expect((capturedRequest["url"] as? String)?.hasSuffix("API_KEY=%5Bredacted%5D&keyword=telescope") == true)
        let query = try #require(capturedRequest["queryString"] as? [[String: String]])
        #expect(query.contains(["name": "API_KEY", "value": "[redacted]"]))
        for message in [capturedRequest, capturedResponse] {
            #expect(message["cookies"] as? [[String: String]] == [
                ["name": "first", "value": "[redacted]"], ["name": "second", "value": "[redacted]"],
            ])
        }
        let content = try #require(capturedResponse["content"] as? [String: Any])
        #expect(content["text"] as? String ==
            #"{"items":[{"author":"pilot","note":"eyJhbGci.eyJzdWIi.redacted","password":"[redacted]"}]}"#)
    }

    @Test("In-memory request bodies are sanitized before entering trace history")
    func inMemoryRequestBodyIsSanitized() throws {
        let secret = "example-secret-8297"
        let bytes = Data("client_secret=\(secret)&author=pilot".utf8)
        let url = try #require(URL(string: "https://api.example.test/"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bytes
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let configuration = APITraceURLProtocolContext.Configuration(
            recorder: APITraceRecorder(maxRecords: 1), redactor: .default, maxBodyBytes: 1024,
            captureRequestBodies: true, captureResponseBodies: false
        )
        let payload = APITraceURLProtocol.makeRequestPayload(
            from: request, redactedURL: configuration.redactor.redact(url: url), configuration: configuration
        )
        #expect(payload.bodyText == "client_secret=%5Bredacted%5D&author=pilot")
        #expect(request.httpBody == bytes)
    }

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
