@testable import APITraceCore
import Foundation
import Testing

@Suite("APITrace HAR export")
struct APITraceHARExportTests {

    // Fixed record for deterministic assertions
    private static let record = APITraceRecord(
        id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
        startedAt: Date(timeIntervalSince1970: 1_741_143_000),
        durationMs: 84,
        method: "GET",
        url: "https://api.example.com/v1/users?page=1&token=%3Cmocked%3E",
        endpoint: "/v1/users",
        request: APITraceRequest(
            headers: ["X-Trace-Id": APITraceCapturedField(mode: .exact, values: ["trace-123"])],
            queryItems: [
                "page": APITraceCapturedField(mode: .exact, values: ["1"]),
                "token": APITraceCapturedField(mode: .includes, values: ["<mocked>"]),
            ]
        ),
        response: APITraceResponse(
            statusCode: 200,
            headers: ["Content-Type": ["application/json; charset=utf-8"]],
            bodyText: #"{"ok":true}"#
        )
    )

    private func har(for records: [APITraceRecord] = [Self.record]) throws -> [String: Any] {
        let data = try APITrace.harData(for: records, prettyPrinted: false)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    @Test("Top-level log object is present with correct version and creator")
    func topLevelStructure() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        #expect(log["version"] as? String == "1.2")
        let creator = try #require(log["creator"] as? [String: Any])
        #expect(creator["name"] as? String == "APITrace")
    }

    @Test("Entry count matches record count")
    func entryCount() throws {
        let root = try har(for: [Self.record, Self.record])
        let log = try #require(root["log"] as? [String: Any])
        let entries = try #require(log["entries"] as? [[String: Any]])
        #expect(entries.count == 2)
    }

    @Test("Entry timing fields are correctly mapped")
    func entryTimings() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        #expect(entry["time"] as? Int == 84)
        let timings = try #require(entry["timings"] as? [String: Any])
        #expect(timings["send"] as? Int == 0)
        #expect(timings["wait"] as? Int == 84)
        #expect(timings["receive"] as? Int == 0)
    }

    @Test("Request method and URL are mapped")
    func requestMethodAndURL() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let request = try #require(entry["request"] as? [String: Any])
        #expect(request["method"] as? String == "GET")
        #expect(request["url"] as? String == "https://api.example.com/v1/users?page=1&token=%3Cmocked%3E")
        #expect(request["httpVersion"] as? String == "HTTP/1.1")
    }

    @Test("Request headers are flattened to name-value pairs")
    func requestHeadersFlattened() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let request = try #require(entry["request"] as? [String: Any])
        let headers = try #require(request["headers"] as? [[String: Any]])
        #expect(headers.count == 1)
        #expect(headers[0]["name"] as? String == "X-Trace-Id")
        #expect(headers[0]["value"] as? String == "trace-123")
    }

    @Test("Request queryString is flattened to name-value pairs")
    func requestQueryStringFlattened() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let request = try #require(entry["request"] as? [String: Any])
        let qs = try #require(request["queryString"] as? [[String: Any]])
        #expect(qs.count == 2)
        let names = Set(qs.compactMap { $0["name"] as? String })
        #expect(names == ["page", "token"])
    }

    @Test("Response status and content are mapped")
    func responseFields() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        #expect(response["status"] as? Int == 200)
        #expect(response["httpVersion"] as? String == "HTTP/1.1")
        let content = try #require(response["content"] as? [String: Any])
        #expect(content["text"] as? String == #"{"ok":true}"#)
        #expect(content["mimeType"] as? String == "application/json")
        #expect(content["size"] as? Int == #"{"ok":true}"#.utf8.count)
        #expect(content["encoding"] == nil)
    }

    @Test("Binary response bodies are exported as base64 with encoding marker")
    func binaryResponseBodyExportedAsBase64() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let record = APITraceRecord(
            durationMs: 10,
            method: "GET",
            url: "https://api.example.com/logo",
            endpoint: "/logo",
            request: APITraceRequest(),
            response: APITraceResponse(
                statusCode: 200,
                headers: ["content-type": ["image/jpeg"]],
                bodyBase64: bytes.base64EncodedString()
            )
        )
        let root = try har(for: [record])
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        let content = try #require(response["content"] as? [String: Any])
        #expect(content["text"] as? String == bytes.base64EncodedString())
        #expect(content["encoding"] as? String == "base64")
        #expect(content["size"] as? Int == bytes.count)
        // Content-Type lookup must be case-insensitive.
        #expect(content["mimeType"] as? String == "image/jpeg")
    }

    @Test("Location header is surfaced as redirectURL")
    func locationHeaderBecomesRedirectURL() throws {
        let record = APITraceRecord(
            durationMs: 5,
            method: "GET",
            url: "https://api.example.com/old",
            endpoint: "/old",
            request: APITraceRequest(),
            response: APITraceResponse(
                statusCode: 301,
                headers: ["Location": ["https://api.example.com/new"]]
            )
        )
        let root = try har(for: [record])
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        #expect(response["redirectURL"] as? String == "https://api.example.com/new")
    }

    @Test("postData mimeType is taken from captured Content-Type header")
    func postDataMimeTypeFromCapturedHeader() throws {
        let record = APITraceRecord(
            durationMs: 5,
            method: "POST",
            url: "https://api.example.com/items",
            endpoint: "/items",
            request: APITraceRequest(
                headers: ["Content-Type": APITraceCapturedField(mode: .exact, values: ["application/json; charset=utf-8"])],
                bodyText: #"{"name":"x"}"#
            )
        )
        let root = try har(for: [record])
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let request = try #require(entry["request"] as? [String: Any])
        let postData = try #require(request["postData"] as? [String: Any])
        #expect(postData["mimeType"] as? String == "application/json")
        #expect(postData["text"] as? String == #"{"name":"x"}"#)
    }

    @Test("Response headers are flattened to name-value pairs")
    func responseHeadersFlattened() throws {
        let root = try har()
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        let headers = try #require(response["headers"] as? [[String: Any]])
        #expect(headers.count == 1)
        #expect(headers[0]["name"] as? String == "Content-Type")
        #expect(headers[0]["value"] as? String == "application/json; charset=utf-8")
    }

    @Test("Failed request produces stub response with status 0")
    func failedRequestStubResponse() throws {
        let failed = APITraceRecord(
            durationMs: 200,
            method: "POST",
            url: "https://api.example.com/v1/items",
            endpoint: "/v1/items",
            request: APITraceRequest(),
            response: nil,
            errorMessage: "The operation couldn't be completed."
        )
        let root = try har(for: [failed])
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        #expect(response["status"] as? Int == 0)
    }

    @Test("Empty records produce empty entries array")
    func emptyRecords() throws {
        let root = try har(for: [])
        let log = try #require(root["log"] as? [String: Any])
        let entries = try #require(log["entries"] as? [[String: Any]])
        #expect(entries.isEmpty)
    }
}
