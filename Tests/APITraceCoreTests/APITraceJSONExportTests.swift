@testable import APITraceCore
import Foundation
import Testing

@Suite("APITrace JSON export")
struct APITraceJSONExportTests {

    private static let record = APITraceRecord(
        id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
        startedAt: Date(timeIntervalSince1970: 1_741_143_000),
        durationMs: 84,
        method: "GET",
        url: "https://api.example.com/v1/users",
        endpoint: "/v1/users",
        request: APITraceRequest(),
        response: APITraceResponse(statusCode: 200)
    )

    @Test("startedAt is exported as ISO 8601 with millisecond precision")
    func startedAtWireFormat() throws {
        let data = try APITrace.jsonData(for: [Self.record], prettyPrinted: false)
        let json = try JSONSerialization.jsonObject(with: data)
        let records = try #require(json as? [[String: Any]])
        let exported = try #require(records.first)
        #expect(exported["startedAt"] as? String == "2025-03-05T02:50:00.000Z")
        #expect(exported["durationMs"] as? Int == 84)
    }
}
