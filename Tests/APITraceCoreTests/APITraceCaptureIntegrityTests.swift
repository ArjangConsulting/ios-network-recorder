import Foundation
import Testing

@testable import APITraceCore

struct APITraceCaptureIntegrityTests {
    @Test func exportsIncompleteCaptureAndTransportFailure() throws {
        let record = APITraceRecord(
            durationMs: 20, method: "GET", url: "https://example.test/events", endpoint: "/events",
            request: APITraceRequest(),
            response: APITraceResponse(
                statusCode: 200, headers: ["Content-Type": ["text/event-stream"]], bodyText: "data: part",
                bodyCapture: APITraceBodyCapture(
                    capturedByteCount: 10, observedByteCount: 100, isTruncated: true, isComplete: false
                )
            ), errorMessage: "cancelled"
        )
        let data = try APITrace.harData(for: [record], prettyPrinted: false)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let log = try #require(root["log"] as? [String: Any])
        let entry = try #require((log["entries"] as? [[String: Any]])?.first)
        let response = try #require(entry["response"] as? [String: Any])
        let capture = try #require(response["_capture"] as? [String: Any])
        #expect(capture["capturedByteCount"] as? Int == 10)
        #expect(capture["observedByteCount"] as? Int == 100)
        #expect(capture["isTruncated"] as? Bool == true)
        #expect(capture["isComplete"] as? Bool == false)
        #expect((response["content"] as? [String: Any])?["size"] as? Int == 100)
        #expect(entry["_error"] as? String == "cancelled")
    }

    @Test func olderResponseRecordsRemainDecodable() throws {
        let response = try JSONDecoder().decode(APITraceResponse.self, from: Data(#"{"statusCode":200,"headers":{},"bodyText":"ok"}"#.utf8))
        #expect(response.bodyCapture == nil)
    }
}
