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
    /// "base64" when `text` holds base64-encoded binary content (HAR 1.2).
    let encoding: String?
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
        let mimeType = harMimeType(
            fromContentType: firstHeaderValue(named: "Content-Type", in: record.request.headers)
        )
        postData = record.request.bodyText.map { HARPostData(mimeType: mimeType, text: $0) }
    }
}

extension HARResponse {
    static let failed = HARResponse(
        status: 0,
        statusText: "",
        httpVersion: "HTTP/1.1",
        headers: [],
        cookies: [],
        content: HARContent(size: 0, mimeType: "", text: nil, encoding: nil),
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
        let mimeType = harMimeType(
            fromContentType: firstHeaderValue(named: "Content-Type", in: response.headers)
        )
        if let text = response.bodyText {
            content = HARContent(size: text.utf8.count, mimeType: mimeType, text: text, encoding: nil)
        } else if let base64 = response.bodyBase64 {
            content = HARContent(
                size: Data(base64Encoded: base64)?.count ?? 0,
                mimeType: mimeType,
                text: base64,
                encoding: "base64"
            )
        } else {
            content = HARContent(size: 0, mimeType: mimeType, text: nil, encoding: nil)
        }
        redirectURL = firstHeaderValue(named: "Location", in: response.headers) ?? ""
        headersSize = -1
        bodySize = -1
    }
}

// MARK: - Header helpers

private func firstHeaderValue(named name: String, in headers: APITraceHeaders) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.first
}

private func firstHeaderValue(named name: String, in fields: APITraceCapturedFields) -> String? {
    fields.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.values.first
}

private func harMimeType(fromContentType value: String?) -> String {
    value?
        .components(separatedBy: ";").first?
        .trimmingCharacters(in: .whitespaces) ?? ""
}
