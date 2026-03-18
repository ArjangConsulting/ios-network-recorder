import Foundation

/// Sanitizes request metadata before it is persisted in trace history.
public struct APITraceRedactor: Sendable {
    public let headerRules: [String: APITraceCaptureMode]
    public let queryItemRules: [String: APITraceCaptureMode]
    public let replacement: String

    public init(
        headerRules: [String: APITraceCaptureMode] = [:],
        queryItemRules: [String: APITraceCaptureMode] = [:],
        replacement: String = "<mocked>"
    ) {
        self.headerRules = Dictionary(
            uniqueKeysWithValues: headerRules.map { ($0.key.lowercased(), $0.value) }
        )
        self.queryItemRules = queryItemRules
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

    /// Captures only the configured query items and rebuilds a sanitized URL.
    public func redact(url: URL) -> APITraceRedactedURL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return APITraceRedactedURL(url: url.absoluteString, queryItems: [:])
        }

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

    public static let `default` = APITraceRedactor()
}
