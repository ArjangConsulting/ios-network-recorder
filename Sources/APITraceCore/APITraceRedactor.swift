import Foundation

/// Sanitizes request metadata before it is persisted in trace history.
public struct APITraceRedactor: Sendable {
    public let headerRules: [String: APITraceCaptureMode]
    public let queryItemRules: [String: APITraceCaptureMode]
    public let responseHeaderRules: [String: APITraceCaptureMode]
    public let replacement: String

    /// Response headers that carry credentials or session material and are
    /// therefore redacted unless a rule explicitly opts them back in.
    public static let defaultResponseHeaderRules: [String: APITraceCaptureMode] = [
        "Set-Cookie": .includes,
        "Set-Cookie2": .includes,
        "Authorization": .includes,
        "Content-Location": .includes,
        "Location": .includes,
        "Proxy-Authenticate": .includes,
        "Refresh": .includes,
        "WWW-Authenticate": .includes,
    ]

    public init(
        headerRules: [String: APITraceCaptureMode] = [:],
        queryItemRules: [String: APITraceCaptureMode] = [:],
        responseHeaderRules: [String: APITraceCaptureMode] = [:],
        replacement: String = "<mocked>"
    ) {
        self.headerRules = Self.normalized(headerRules)
        self.queryItemRules = queryItemRules
        self.responseHeaderRules = Self.normalized(
            APITraceRedactor.defaultResponseHeaderRules.merging(responseHeaderRules) { _, custom in custom }
        )
        self.replacement = replacement
    }

    /// Captures only the configured request headers.
    public func redact(headers: APITraceHeaders) -> APITraceCapturedFields {
        var output: APITraceCapturedFields = [:]
        output.reserveCapacity(headers.count)

        for (name, values) in headers {
            guard let mode = headerRules[name.lowercased()] else {
                continue
            }
            output[name] = makeCapturedField(mode: mode, originalValues: values)
        }

        return output
    }

    /// Convenience overload for single-value header dictionaries.
    public func redact(singleValueHeaders: [String: String]) -> APITraceCapturedFields {
        let normalized = singleValueHeaders.mapValues { [$0] }
        return redact(headers: normalized)
    }

    /// Sanitizes response headers. Unlike request headers, response headers are
    /// captured by default; headers with an `includes` rule keep presence only.
    public func redact(responseHeaders: APITraceHeaders) -> APITraceHeaders {
        var output: APITraceHeaders = [:]
        output.reserveCapacity(responseHeaders.count)

        for (name, values) in responseHeaders {
            let mode = responseHeaderRules[name.lowercased()] ?? .exact
            output[name] = values.map { sanitizedValue(for: mode, originalValue: $0) }
        }

        return output
    }

    /// Strips query strings from URLs embedded in error messages, which would
    /// otherwise bypass query-item redaction.
    public func redact(errorMessage: String) -> String {
        errorMessage.replacingOccurrences(
            of: #"(https?://[^\s?'"<>]*)\?[^\s'"<>]*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    /// Captures only the configured query items and rebuilds a sanitized URL.
    public func redact(url: URL) -> APITraceRedactedURL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return APITraceRedactedURL(url: url.absoluteString, queryItems: [:])
        }

        components.user = nil
        components.password = nil
        components.fragment = nil

        let originalItems = components.queryItems ?? []
        if originalItems.isEmpty {
            return APITraceRedactedURL(url: components.string ?? url.absoluteString, queryItems: [:])
        }

        var capturedItems: APITraceCapturedFields = [:]
        var sanitizedQueryItems: [URLQueryItem] = []

        for item in originalItems {
            guard let mode = queryItemRules[item.name] else {
                continue
            }

            let originalValue = item.value ?? ""
            let sanitizedValue = sanitizedValue(for: mode, originalValue: originalValue)
            sanitizedQueryItems.append(URLQueryItem(name: item.name, value: sanitizedValue))

            if let existing = capturedItems[item.name] {
                capturedItems[item.name] = APITraceCapturedField(
                    mode: existing.mode,
                    values: existing.values + [sanitizedValue]
                )
            } else {
                capturedItems[item.name] = APITraceCapturedField(mode: mode, values: [sanitizedValue])
            }
        }

        components.queryItems = sanitizedQueryItems.isEmpty ? nil : sanitizedQueryItems
        return APITraceRedactedURL(
            url: components.string ?? url.absoluteString,
            queryItems: capturedItems
        )
    }

    private func makeCapturedField(mode: APITraceCaptureMode, originalValues: [String]) -> APITraceCapturedField {
        APITraceCapturedField(
            mode: mode,
            values: originalValues.map { sanitizedValue(for: mode, originalValue: $0) }
        )
    }

    private func sanitizedValue(for mode: APITraceCaptureMode, originalValue: String) -> String {
        switch mode {
        case .exact:
            return originalValue
        case .includes:
            return replacement
        }
    }

    private static func normalized(_ rules: [String: APITraceCaptureMode]) -> [String: APITraceCaptureMode] {
        var normalized: [String: APITraceCaptureMode] = [:]
        for (name, mode) in rules {
            normalized[name.lowercased()] = mode
        }
        return normalized
    }

    public static let `default` = APITraceRedactor()
}
