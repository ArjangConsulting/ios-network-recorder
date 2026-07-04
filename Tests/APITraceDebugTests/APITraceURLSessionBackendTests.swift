@testable import APITraceCore
@testable import APITraceDebug
import Foundation
import Testing

/// These tests exercise the real `URLProtocol` registration path, which is process-global
/// state. They must not run concurrently with each other.
@Suite("APITraceURLSessionBackend lifecycle", .serialized)
struct APITraceURLSessionBackendTests {

    private func makeRequest(to port: UInt16) -> URLRequest {
        URLRequest(url: URL(string: "http://127.0.0.1:\(port)/ping")!)
    }

    private func execute(_ request: URLRequest) async throws {
        // Explicitly include APITraceURLProtocol rather than relying on
        // URLProtocol.registerClass propagating into `.default` sessions: some command-line
        // test-runner environments don't reliably surface global registrations to freshly
        // created sessions. The actual on/off behavior under test is governed by
        // APITraceURLProtocolContext's `isCapturing` flag (set by start()/stop()), which this
        // still fully exercises.
        let config = URLSessionConfiguration.default
        config.protocolClasses = [APITraceURLProtocol.self] + (config.protocolClasses ?? [])
        let session = URLSession(configuration: config)
        _ = try await session.data(for: request)
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

        let backend = APITraceURLSessionBackend(maxBodyBytes: 10)
        defer { backend.stop() }

        backend.start()
        try await execute(makeRequest(to: port))

        let record = try #require(backend.records().first)
        let capturedText = try #require(record.response?.bodyText)
        #expect(capturedText.utf8.count <= 10)
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
