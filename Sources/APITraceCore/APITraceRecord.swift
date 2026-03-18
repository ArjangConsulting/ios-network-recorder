import Foundation

/// Header collection that preserves multi-value entries and custom headers.
public typealias APITraceHeaders = [String: [String]]
/// Request metadata captured according to the configured sanitization policy.
public typealias APITraceCapturedFields = [String: APITraceCapturedField]

/// How a request field should be persisted in trace history.
public enum APITraceCaptureMode: String, Codable, Sendable {
    case exact
    case includes
}

/// Sanitized representation of a captured request field.
public struct APITraceCapturedField: Codable, Equatable, Sendable {
    public let mode: APITraceCaptureMode
    public let values: [String]

    public init(mode: APITraceCaptureMode, values: [String]) {
        self.mode = mode
        self.values = values
    }
}

/// Sanitized request URL plus the captured query items derived from it.
public struct APITraceRedactedURL: Equatable, Sendable {
    public let url: String
    public let queryItems: APITraceCapturedFields

    public init(url: String, queryItems: APITraceCapturedFields) {
        self.url = url
        self.queryItems = queryItems
    }
}

/// Request payload captured by APITrace.
public struct APITraceRequest: Codable, Sendable {
    public let headers: APITraceCapturedFields
    public let queryItems: APITraceCapturedFields
    public let bodyText: String?
    public let bodyBase64: String?

    public init(
        headers: APITraceCapturedFields = [:],
        queryItems: APITraceCapturedFields = [:],
        bodyText: String? = nil,
        bodyBase64: String? = nil
    ) {
        self.headers = headers
        self.queryItems = queryItems
        self.bodyText = bodyText
        self.bodyBase64 = bodyBase64
    }
}

/// Response payload captured by APITrace.
public struct APITraceResponse: Codable, Sendable {
    public let statusCode: Int
    public let headers: APITraceHeaders
    public let bodyText: String?
    public let bodyBase64: String?

    public init(
        statusCode: Int,
        headers: APITraceHeaders = [:],
        bodyText: String? = nil,
        bodyBase64: String? = nil
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.bodyText = bodyText
        self.bodyBase64 = bodyBase64
    }
}

/// One network exchange record (request + response/failure).
public struct APITraceRecord: Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let durationMs: Int
    public let method: String
    public let url: String
    public let endpoint: String
    public let request: APITraceRequest
    public let response: APITraceResponse?
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        durationMs: Int,
        method: String,
        url: String,
        endpoint: String,
        request: APITraceRequest,
        response: APITraceResponse? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.method = method
        self.url = url
        self.endpoint = endpoint
        self.request = request
        self.response = response
        self.errorMessage = errorMessage
    }
}
