@testable import APITraceCore
@testable import APITraceDebug
import Foundation
import Testing

/// These tests exercise the real `URLProtocol` registration path, which is process-global
/// state. They must not run concurrently with each other.
@Suite("APITraceURLSessionBackend lifecycle", .serialized)
struct APITraceURLSessionBackendTests {

    private func makeRequest(to port: UInt16, path: String = "/ping") -> URLRequest {
        URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    }

    @discardableResult
    private func execute(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Use the public custom-configuration opt-in rather than relying on
        // URLProtocol.registerClass propagating into `.default` sessions: some command-line
        // test-runner environments don't reliably surface global registrations to freshly
        // created sessions. The actual on/off behavior under test is governed by
        // APITraceURLProtocolContext's `isCapturing` flag (set by start()/stop()), which this
        // still fully exercises.
        let config = URLSessionConfiguration.default
        APITraceDebugBootstrap.enableCapture(in: config)
        let session = URLSession(configuration: config)
        return try await session.data(for: request)
    }

    @Test("Capture is disabled by default until start() is called")
    func captureDisabledBeforeStart() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }

        try await execute(makeRequest(to: port))

        #expect(backend.records().isEmpty)
    }

    @Test("Capture records requests after start() is called")
    func captureRecordsAfterStart() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))

        #expect(backend.records().count == 1)
    }

    @Test("Capture stops recording after stop() is called")
    func captureStopsAfterStop() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))
        backend.stop()
        try await execute(makeRequest(to: port))

        #expect(backend.records().count == 1)
    }

    @Test("Capture resumes if start() is called again after stop()")
    func captureResumesAfterRestart() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))
        backend.stop()
        backend.start()
        try await execute(makeRequest(to: port))

        #expect(backend.records().count == 2)
    }

    @Test("Response body capture is truncated to maxBodyBytes")
    func responseBodyTruncatedToMaxBodyBytes() async throws {
        let longBody = String(repeating: "x", count: 200)
        let server = LoopbackHTTPServer(responseBody: longBody)
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(maxBodyBytes: 10, captureResponseBodies: true)
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))

        let record = try #require(backend.records().first)
        let capturedText = try #require(record.response?.bodyText)
        #expect(capturedText.utf8.count <= 10)
    }

    @Test("POST request bodies are captured and still delivered to the server")
    func requestBodyIsCapturedAndForwarded() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(captureRequestBodies: true)
        defer { backend.stop() }
        backend.start()

        let payload = #"{"name":"widget"}"#
        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBody = Data(payload.utf8)
        try await execute(request)

        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == payload)
        #expect(server.bodies.map { String(decoding: $0, as: UTF8.self) } == [payload])
    }

    @Test("Streamed request bodies with a known length are captured and forwarded")
    func streamedBodyWithKnownLengthIsCaptured() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(captureRequestBodies: true)
        defer { backend.stop() }
        backend.start()

        let payload = Data(#"{"text":"hello"}"#.utf8)
        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: payload)
        request.setValue("\(payload.count)", forHTTPHeaderField: "Content-Length")
        try await execute(request)

        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == String(decoding: payload, as: UTF8.self))
        #expect(server.bodies == [payload])
    }

    @Test("Streamed request bodies of unknown length are forwarded untouched and not captured")
    func streamedBodyWithUnknownLengthIsNotCaptured() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(captureRequestBodies: true)
        defer { backend.stop() }
        backend.start()

        let payload = Data("chunked-payload".utf8)
        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: payload)
        let (_, response) = try await execute(request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == nil)
    }

    @Test("Request body capture is truncated to maxBodyBytes while the full body is forwarded")
    func requestBodyTruncatedToMaxBodyBytes() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(maxBodyBytes: 10, captureRequestBodies: true)
        defer { backend.stop() }
        backend.start()

        let payload = Data(String(repeating: "z", count: 200).utf8)
        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBody = payload
        try await execute(request)

        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == String(repeating: "z", count: 10))
        #expect(server.bodies == [payload])
    }

    @Test("Bodies are not captured by default")
    func bodyCaptureDefaultsOff() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(maxBodyBytes: 10)
        defer { backend.stop() }
        backend.start()

        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBody = Data(String(repeating: "y", count: 200).utf8)
        try await execute(request)

        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == nil)
        #expect(record.response?.bodyText == nil)
    }

    @Test("Body capture can be disabled while headers are still recorded")
    func bodyCaptureOptOut() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend(captureRequestBodies: false, captureResponseBodies: false)
        defer { backend.stop() }
        backend.start()

        var request = makeRequest(to: port)
        request.httpMethod = "POST"
        request.httpBody = Data("secret-payload".utf8)
        try await execute(request)

        let record = try #require(backend.records().first)
        #expect(record.request.bodyText == nil)
        #expect(record.request.bodyBase64 == nil)
        #expect(record.response?.bodyText == nil)
        #expect(record.response?.bodyBase64 == nil)
        #expect(record.response?.statusCode == 200)
    }

    @Test("Sensitive response headers are redacted by default")
    func sensitiveResponseHeadersRedacted() async throws {
        let server = LoopbackHTTPServer(routes: [
            "/login": LoopbackHTTPServer.Route(
                headers: ["Set-Cookie: session=super-secret; HttpOnly", "X-Request-Id: req-7"]
            ),
        ])
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }
        backend.start()

        try await execute(makeRequest(to: port, path: "/login"))

        let record = try #require(backend.records().first)
        let headers = try #require(record.response?.headers)
        #expect(headers["Set-Cookie"] == ["<mocked>"])
        #expect(headers["X-Request-Id"] == ["req-7"])
    }

    @Test("Redirects are handed back to the app and each hop is recorded")
    func redirectsRecordedPerHop() async throws {
        let server = LoopbackHTTPServer(routes: [
            "/old": LoopbackHTTPServer.Route(
                status: 302,
                reason: "Found",
                headers: ["Location: /ping"],
                body: ""
            ),
        ])
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }
        backend.start()

        let (data, response) = try await execute(makeRequest(to: port, path: "/old"))

        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        let records = backend.records()
        #expect(records.count == 2)
        let hop = try #require(records.first)
        #expect(hop.endpoint == "/old")
        #expect(hop.response?.statusCode == 302)
        let final = try #require(records.last)
        #expect(final.endpoint == "/ping")
        #expect(final.response?.statusCode == 200)
    }

    @Test("clear() removes all captured records")
    func clearRemovesRecords() async throws {
        let server = LoopbackHTTPServer()
        let port = try server.start()
        defer { server.stop() }

        let backend = APITraceURLSessionBackend()
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))
        backend.clear()

        #expect(backend.records().isEmpty)
    }
}
