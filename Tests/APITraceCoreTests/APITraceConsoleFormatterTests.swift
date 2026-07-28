import XCTest

@testable import APITraceCore

final class APITraceConsoleFormatterTests: XCTestCase {
    func testFormatsSuccessfulExchangeWithIndentedSections() {
        let record = APITraceRecord(
            durationMs: 42,
            method: "POST",
            url: "https://api.example.com/videos",
            endpoint: "/videos",
            request: APITraceRequest(
                headers: [
                    "Content-Type": APITraceCapturedField(
                        mode: .exact,
                        values: ["application/json"]
                    ),
                    "X-Request-ID": APITraceCapturedField(mode: .exact, values: ["trace-123"]),
                ],
                bodyText: "{\n  \"title\": \"Hello\"\n}"
            ),
            response: APITraceResponse(
                statusCode: 201,
                headers: ["Content-Type": ["application/json"]],
                bodyText: "{\n  \"id\": 7\n}"
            )
        )

        XCTAssertEqual(
            APITraceConsoleFormatter().format(record),
            """
            → REQUEST POST https://api.example.com/videos
              Headers:
                Content-Type: application/json
                X-Request-ID: trace-123
              Body:
                {
                  "title": "Hello"
                }
            ← RESPONSE 201 (42ms)
              Headers:
                Content-Type: application/json
              Body:
                {
                  "id": 7
                }
            """
        )
    }

    func testFormatsFailureAndEmptyRequestSections() {
        let record = APITraceRecord(
            durationMs: 8,
            method: "GET",
            url: "https://api.example.com/videos",
            endpoint: "/videos",
            request: APITraceRequest(),
            errorMessage: "Connection refused"
        )

        XCTAssertEqual(
            APITraceConsoleFormatter().format(record),
            """
            → REQUEST GET https://api.example.com/videos
              Headers:
                <none>
              Body:
                <empty>
            ✗ FAILURE (8ms)
              Error:
                Connection refused
            """
        )
    }

    func testTruncatesTextAndDescribesBinaryBodies() {
        let record = APITraceRecord(
            durationMs: 1,
            method: "POST",
            url: "https://api.example.com/upload",
            endpoint: "/upload",
            request: APITraceRequest(bodyText: "abcdef"),
            response: APITraceResponse(statusCode: 200, bodyBase64: "AQID")
        )

        let output = APITraceConsoleFormatter(maxBodyCharacters: 3).format(record)

        XCTAssertTrue(output.contains("abc…[truncated]"))
        XCTAssertTrue(output.contains("<binary body: base64, 4 characters>"))
    }
}
