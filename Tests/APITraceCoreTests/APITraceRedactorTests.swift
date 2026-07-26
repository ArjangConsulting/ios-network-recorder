import APITraceCore
import Foundation
import Testing

@Suite("APITraceRedactor")
struct APITraceRedactorTests {
    @Test("Request capture is opt-in for headers and query items")
    func requestCaptureIsOptIn() throws {
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

        #expect(headers.count == 2)
        #expect(headers["Authorization"] == APITraceCapturedField(mode: .includes, values: ["<mocked>"]))
        #expect(headers["X-Trace-Id"] == APITraceCapturedField(mode: .exact, values: ["trace-123"]))
        #expect(headers["Accept"] == nil)

        let url = try #require(URL(string: "https://api.example.com/v1/users?page=1&token=secret&token=backup&ignored=true"))
        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users?page=1&token=%3Cmocked%3E&token=%3Cmocked%3E")
        #expect(redactedURL.queryItems["page"] == APITraceCapturedField(mode: .exact, values: ["1"]))
        #expect(redactedURL.queryItems["token"] == APITraceCapturedField(mode: .includes, values: ["<mocked>", "<mocked>"]))
        #expect(redactedURL.queryItems["ignored"] == nil)
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
        #expect(headers["set-cookie"] == ["<mocked>", "<mocked>"])
        #expect(headers["WWW-Authenticate"] == ["<mocked>"])
        #expect(headers["X-Request-Id"] == ["req-42"])
    }

    @Test("Response header rules can opt sensitive headers back in or add new ones")
    func responseHeaderRulesAreOverridable() {
        let redactor = APITraceRedactor(
            responseHeaderRules: [
                "Set-Cookie": .exact,
                "X-Internal-Token": .includes,
            ]
        )

        let headers = redactor.redact(responseHeaders: [
            "Set-Cookie": ["session=abc123"],
            "X-Internal-Token": ["secret"],
            "WWW-Authenticate": ["Bearer secret"],
        ])

        #expect(headers["Set-Cookie"] == ["session=abc123"])
        #expect(headers["X-Internal-Token"] == ["<mocked>"])
        #expect(headers["WWW-Authenticate"] == ["<mocked>"])
    }

    @Test("Error messages have URL query strings stripped")
    func errorMessagesLoseQueryStrings() {
        let redactor = APITraceRedactor.default

        let sanitized = redactor.redact(
            errorMessage: "Could not connect to https://api.example.com/v1/users?token=secret&page=1."
        )
        #expect(sanitized == "Could not connect to https://api.example.com/v1/users")

        let untouched = redactor.redact(errorMessage: "The request timed out. Retry? Yes/no")
        #expect(untouched == "The request timed out. Retry? Yes/no")
    }

    @Test("Default redactor drops request metadata until configured")
    func defaultRedactorDropsRequestMetadata() throws {
        let redactor = APITraceRedactor.default

        let headers = redactor.redact(singleValueHeaders: [
            "Authorization": "Bearer secret-token",
            "X-Trace-Id": "trace-123",
        ])
        #expect(headers.isEmpty)

        let url = try #require(URL(string: "https://api.example.com/v1/users?page=1&token=secret"))
        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users")
        #expect(redactedURL.queryItems.isEmpty)
    }

    @Test("URL credentials and fragments are always removed")
    func urlCredentialsAndFragmentsAreRemoved() throws {
        let redactor = APITraceRedactor(queryItemRules: ["page": .exact])
        let url = try #require(URL(string: "https://user:password@api.example.com/v1/users?page=1#access-token"))

        let redactedURL = redactor.redact(url: url)

        #expect(redactedURL.url == "https://api.example.com/v1/users?page=1")
    }
}
