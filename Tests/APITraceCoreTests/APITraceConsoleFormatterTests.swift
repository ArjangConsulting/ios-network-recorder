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
                  "title" : "Hello"
                }
            ← RESPONSE 201 (42ms)
              Headers:
                Content-Type: application/json
              Body:
                {
                  "id" : 7
                }
            """
        )
    }

    func testFormatsFailureAndOmitsEmptyRequestBody() {
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

    func testPrettyPrintsCompactJSONObjectAndArrayBodies() {
        let record = APITraceRecord(
            durationMs: 1,
            method: "POST",
            url: "https://api.example.com/items",
            endpoint: "/items",
            request: APITraceRequest(bodyText: #"{"request":{"value":true}}"#),
            response: APITraceResponse(statusCode: 200, bodyText: #"[{"id":1},{"id":2}]"#)
        )

        let output = APITraceConsoleFormatter().format(record)

        XCTAssertFalse(output.contains(#"{"request":{"value":true}}"#))
        XCTAssertFalse(output.contains(#"[{"id":1},{"id":2}]"#))
        XCTAssertTrue(output.contains("\n      \"request\" : {"))
        XCTAssertTrue(output.contains("\n        \"value\" : true"))
        XCTAssertTrue(output.contains("\n      {"))
    }

    func testOmitsEmptyWhitespaceAndEmptyBinaryBodies() {
        let record = APITraceRecord(
            durationMs: 1,
            method: "POST",
            url: "https://api.example.com/items",
            endpoint: "/items",
            request: APITraceRequest(bodyText: " \n\t "),
            response: APITraceResponse(statusCode: 204, bodyBase64: "")
        )

        let output = APITraceConsoleFormatter().format(record)

        XCTAssertFalse(output.contains("Body:"))
        XCTAssertFalse(output.contains("<empty>"))
    }

    func testPreservesPlainAndMalformedTextBodies() {
        let record = APITraceRecord(
            durationMs: 1,
            method: "POST",
            url: "https://api.example.com/items",
            endpoint: "/items",
            request: APITraceRequest(bodyText: "plain text"),
            response: APITraceResponse(statusCode: 400, bodyText: "{not json}")
        )

        let output = APITraceConsoleFormatter().format(record)

        XCTAssertTrue(output.contains("\n    plain text"))
        XCTAssertTrue(output.contains("\n    {not json}"))
    }

    func testTruncatesAfterPrettyPrintingJSON() {
        let record = APITraceRecord(
            durationMs: 1,
            method: "POST",
            url: "https://api.example.com/items",
            endpoint: "/items",
            request: APITraceRequest(bodyText: #"{"longValue":"abcdefghijk"}"#)
        )

        let output = APITraceConsoleFormatter(maxBodyCharacters: 12).format(record)

        XCTAssertTrue(output.contains("…[truncated]"))
        XCTAssertFalse(output.contains(#"{"longValue""#))
    }
}
