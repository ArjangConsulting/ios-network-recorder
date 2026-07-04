import Foundation

// MARK: - HAR 1.2 model (internal)

struct HARExport: Encodable {
    let log: HARLog
}

struct HARLog: Encodable {
    let version: String
    let creator: HARCreator
    let entries: [HAREntry]
}

struct HARCreator: Encodable {
    let name: String
    let version: String
}

struct HAREntry: Encodable {
    let startedDateTime: Date
    let time: Int
    let request: HARRequest
    let response: HARResponse
    let cache: HARCache
    let timings: HARTimings
}

struct HARNameValue: Encodable {
    let name: String
    let value: String
}

struct HARRequest: Encodable {
    let method: String
    let url: String
    let httpVersion: String
    let headers: [HARNameValue]
    let queryString: [HARNameValue]
    let cookies: [HARNameValue]
    let headersSize: Int
    let bodySize: Int
    let postData: HARPostData?
}

struct HARPostData: Encodable {
    let mimeType: String
    let text: String
}

struct HARResponse: Encodable {
    let status: Int
    let statusText: String
    let httpVersion: String
    let headers: [HARNameValue]
    let cookies: [HARNameValue]
    let content: HARContent
    let redirectURL: String
    let headersSize: Int
    let bodySize: Int
}

struct HARContent: Encodable {
    let size: Int
    let mimeType: String
    let text: String?
}

struct HARCache: Encodable {}

struct HARTimings: Encodable {
    let send: Int
    let wait: Int
    let receive: Int
}

// MARK: - Mapping from APITraceRecord

extension HAREntry {
    init(_ record: APITraceRecord) {
        startedDateTime = record.startedAt
        time = record.durationMs
        request = HARRequest(record)
        response = record.response.map(HARResponse.init) ?? .failed
        cache = HARCache()
        timings = HARTimings(send: 0, wait: record.durationMs, receive: 0)
    }
}

extension HARRequest {
    init(_ record: APITraceRecord) {
        method = record.method
        url = record.url
        httpVersion = "HTTP/1.1"
        headers = record.request.headers.flatMap { name, field in
            field.values.map { HARNameValue(name: name, value: $0) }
        }
        queryString = record.request.queryItems.flatMap { name, field in
            field.values.map { HARNameValue(name: name, value: $0) }
        }
        cookies = []
        headersSize = -1
        bodySize = -1
        postData = record.request.bodyText.map { HARPostData(mimeType: "", text: $0) }
    }
}

extension HARResponse {
    static let failed = HARResponse(
        status: 0,
        statusText: "",
        httpVersion: "HTTP/1.1",
        headers: [],
        cookies: [],
        content: HARContent(size: -1, mimeType: "", text: nil),
        redirectURL: "",
        headersSize: -1,
        bodySize: -1
    )

    init(_ response: APITraceResponse) {
        status = response.statusCode
        statusText = ""
        httpVersion = "HTTP/1.1"
        headers = response.headers.flatMap { name, values in
            values.map { HARNameValue(name: name, value: $0) }
        }
        cookies = []
        let mimeType = response.headers["Content-Type"]?.first?
            .components(separatedBy: ";").first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        content = HARContent(size: -1, mimeType: mimeType, text: response.bodyText)
        redirectURL = ""
        headersSize = -1
        bodySize = -1
    }
}
