import APITraceCore
import Foundation
import Testing

@Suite("APITraceRedactor")
struct APITraceRedactorTests {
    @Test("Request headers are preserved and configured values are sanitized")
    func requestHeadersArePreservedAndSanitized() throws {
        let redactor = APITraceRedactor(
            headerRules: [
                "Authorization": .includes,
                "X-Trace-Id": .exact,
            ],
            queryItemRules: [
                "page": .exact,
                "token": .includes,
            ]
        )

        let headers = redactor.redact(singleValueHeaders: [
            "Authorization": "Bearer secret-token",
            "X-Trace-Id": "trace-123",
            "Accept": "application/json",
        ])

        #expect(headers.count == 3)
        #expect(headers["Authorization"] == APITraceCapturedField(mode: .includes, values: ["[redacted]"]))
        #expect(headers["X-Trace-Id"] == APITraceCapturedField(mode: .exact, values: ["trace-123"]))
        #expect(headers["Accept"] == APITraceCapturedField(mode: .exact, values: ["application/json"]))

        let url = try #require(URL(string: "https://api.example.com/v1/users?page=1&token=secret&token=backup&ignored=true"))
        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users?page=1&token=%5Bredacted%5D&token=%5Bredacted%5D&ignored=true")
        #expect(redactedURL.queryItems["page"] == APITraceCapturedField(mode: .exact, values: ["1"]))
        #expect(redactedURL.queryItems["token"] == APITraceCapturedField(mode: .includes, values: ["[redacted]", "[redacted]"]))
        #expect(redactedURL.queryItems["ignored"]?.values == ["true"])
    }

    @Test("Response headers are captured by default with sensitive defaults redacted")
    func responseHeadersRedactSensitiveDefaults() {
        let redactor = APITraceRedactor.default

        let headers = redactor.redact(responseHeaders: [
            "Content-Type": ["application/json"],
            "set-cookie": ["session=abc123; HttpOnly", "theme=dark"],
            "WWW-Authenticate": ["Bearer realm=\"api\""],
            "X-Request-Id": ["req-42"],
        ])

        #expect(headers["Content-Type"] == ["application/json"])
        #expect(headers["set-cookie"] == ["[redacted]", "[redacted]"])
        #expect(headers["WWW-Authenticate"] == ["[redacted]"])
        #expect(headers["X-Request-Id"] == ["req-42"])
    }

    @Test("Legacy rules can add sensitive headers but exact cannot bypass redaction")
    func responseHeaderRulesAreOverridable() {
        let redactor = APITraceRedactor(
            responseHeaderRules: [
                "Set-Cookie": .exact,
                "X-Internal-Token": .includes,
            ],
            replacement: "<legacy>"
        )

        let headers = redactor.redact(responseHeaders: [
            "Set-Cookie": ["session=abc123"],
            "X-Internal-Token": ["secret"],
            "WWW-Authenticate": ["Bearer secret"],
        ])

        #expect(headers["Set-Cookie"] == ["[redacted]"])
        #expect(headers["X-Internal-Token"] == ["[redacted]"])
        #expect(headers["WWW-Authenticate"] == ["[redacted]"])
    }

    @Test("Free-form error details are not retained")
    func errorDetailsAreOmitted() {
        let redactor = APITraceRedactor.default

        let sanitized = redactor.redact(
            errorMessage: "Could not connect to https://api.example.com/v1/users?token=secret&page=1."
        )
        #expect(sanitized == "Network request failed")

        #expect(redactor.redact(errorMessage: "The request timed out. Retry? Yes/no") == sanitized)
    }

    @Test("Default redactor preserves request metadata")
    func defaultRedactorPreservesRequestMetadata() throws {
        let redactor = APITraceRedactor.default

        let headers = redactor.redact(singleValueHeaders: [
            "Authorization": "Bearer secret-token",
            "X-Trace-Id": "trace-123",
        ])
        #expect(headers["Authorization"] == APITraceCapturedField(mode: .includes, values: ["[redacted]"]))
        #expect(headers["X-Trace-Id"] == APITraceCapturedField(mode: .exact, values: ["trace-123"]))

        let url = try #require(URL(string: "https://api.example.com/v1/users?page=1&token=secret"))
        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users?page=1&token=%5Bredacted%5D")
        #expect(redactedURL.queryItems["page"]?.values == ["1"])
        #expect(redactedURL.queryItems["token"]?.values == ["[redacted]"])
    }

    @Test("URL credentials and fragments are always removed")
    func urlCredentialsAndFragmentsAreRemoved() throws {
        let redactor = APITraceRedactor(queryItemRules: ["page": .exact])
        let url = try #require(URL(string: "https://user:password@api.example.com/v1/users?page=1#access-token"))

        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users?page=1")
    }
}
