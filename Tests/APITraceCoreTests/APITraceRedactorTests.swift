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
}
