import Foundation

/// Sanitizes network data before it enters trace history.
public struct APITraceRedactor: Sendable {
    public let headerRules: [String: APITraceCaptureMode]
    public let queryItemRules: [String: APITraceCaptureMode]
    public let responseHeaderRules: [String: APITraceCaptureMode]
    public let replacement = APITraceCredentialNames.marker

    /// Headers redacted by the default credential policy.
    public static let defaultResponseHeaderRules: [String: APITraceCaptureMode] = Dictionary(
        uniqueKeysWithValues: (APITraceCredentialNames.headers + APITraceCredentialNames.importOnlyHeaders)
            .map { ($0, .includes) }
    )

    private let credentials: APITraceCredentialPolicy
    private let customResponseRules: [String: APITraceCaptureMode]
    private let normalizedHeaderRules: [String: APITraceCaptureMode]
    private let normalizedQueryRules: [String: APITraceCaptureMode]

    public init(
        headerRules: [String: APITraceCaptureMode] = [:],
        queryItemRules: [String: APITraceCaptureMode] = [:],
        responseHeaderRules: [String: APITraceCaptureMode] = [:],
        replacement _: String = "[redacted]",
        redact: APITraceRedactionConfiguration = .init()
    ) {
        self.headerRules = Self.normalized(headerRules, by: { $0.lowercased() })
        self.queryItemRules = queryItemRules
        self.responseHeaderRules = Self.normalized(
            Self.defaultResponseHeaderRules.merging(responseHeaderRules) { _, custom in custom },
            by: { $0.lowercased() }
        )
        self.credentials = APITraceCredentialPolicy(redact)
        self.customResponseRules = Self.normalized(responseHeaderRules, by: APITraceCredentialNames.normalize)
        self.normalizedHeaderRules = Self.normalized(headerRules, by: APITraceCredentialNames.normalize)
        self.normalizedQueryRules = Self.normalized(queryItemRules, by: APITraceCredentialNames.normalize)
    }

    public func redact(headers: APITraceHeaders) -> APITraceCapturedFields {
        headers.reduce(into: [:]) { output, entry in
            let (name, values) = entry
            let rule = headerRule(name, custom: normalizedHeaderRules)
            output[name] = APITraceCapturedField(
                mode: rule.mode,
                values: values.map { sanitizeHeader($0, name: name, rule: rule) }
            )
        }
    }

    public func redact(singleValueHeaders: [String: String]) -> APITraceCapturedFields {
        redact(headers: singleValueHeaders.mapValues { [$0] })
    }

    public func redact(responseHeaders: APITraceHeaders) -> APITraceHeaders {
        responseHeaders.reduce(into: [:]) { output, entry in
            let (name, values) = entry
            let rule = headerRule(name, custom: customResponseRules)
            output[name] = values.map { sanitizeHeader($0, name: name, rule: rule) }
        }
    }

    /// Drops free-form transport details, which can contain unstructured credentials.
    public func redact(errorMessage _: String) -> String {
        Self.networkFailureMessage
    }

    package static let networkFailureMessage = "Network request failed"

    public func redact(url: URL) -> APITraceRedactedURL {
        sanitizeURL(URLComponents(url: url, resolvingAgainstBaseURL: false))
            ?? APITraceRedactedURL(url: APITraceCredentialNames.marker, queryItems: [:])
    }

    /// Returns only valid cookie names, never cookie values or attributes.
    public func cookieNames(in headers: APITraceHeaders, response: Bool = false) -> [String] {
        let headerName = response ? "setcookie" : "cookie"
        return headers.filter { APITraceCredentialNames.normalize($0.key) == headerName }
            .flatMap(\.value)
            .flatMap { value in
                let fields = response
                    ? value.replacingOccurrences(of: Self.setCookieSeparator, with: "\n", options: .regularExpression)
                        .components(separatedBy: "\n")
                    : value.components(separatedBy: ";")
                return fields.compactMap { field -> String? in
                    guard let range = field.range(of: Self.cookieNamePattern, options: .regularExpression) else {
                        return nil
                    }
                    return String(field[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
    }

    /// Sanitizes complete UTF-8 JSON or form data. Uninspectable payloads are not retained.
    public func redact(body: Data, contentType: String?) -> String? {
        guard !body.isEmpty, let text = String(data: body, encoding: .utf8) else { return nil }
        let mediaType = contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if mediaType == "application/x-www-form-urlencoded" {
            return sanitizeParameters(text, form: true)?.encoded
        }
        guard mediaType == "application/json" || mediaType.hasSuffix("+json"),
              let object = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed),
              let sanitized = try? JSONSerialization.data(withJSONObject: sanitizeJSON(object), options: [.fragmentsAllowed, .sortedKeys])
        else { return nil }
        return String(data: sanitized, encoding: .utf8)
    }

    private func sanitizeJSON(_ value: Any, name: String = "") -> Any {
        let rule = parameterRule(name)
        switch rule {
        case .keep:
            return value
        case .replace:
            return APITraceCredentialNames.marker
        case .inspect:
            if let dictionary = value as? [String: Any] {
                return dictionary.reduce(into: [String: Any]()) { output, entry in
                    output[entry.key] = sanitizeJSON(entry.value, name: entry.key)
                }
            }
            if let array = value as? [Any] {
                return array.map { sanitizeJSON($0) }
            }
            if let text = value as? String {
                return Self.stripJWT(text)
            }
            return value
        }
    }

    private func sanitizeURL(_ input: URLComponents?) -> APITraceRedactedURL? {
        guard var components = input else { return nil }
        components.user = nil
        components.password = nil
        components.fragment = nil
        var captured: APITraceCapturedFields = [:]
        if let query = components.percentEncodedQuery, !query.isEmpty {
            guard let sanitized = sanitizeParameters(query, form: false) else { return nil }
            components.percentEncodedQuery = sanitized.encoded
            captured = sanitized.fields
        }
        guard let url = components.string else { return nil }
        let queryStart = url.firstIndex(of: "?") ?? url.endIndex
        let sanitizedURL = Self.stripJWT(String(url[..<queryStart])) + url[queryStart...]
        return APITraceRedactedURL(url: sanitizedURL, queryItems: captured)
    }

    private func sanitizeParameters(_ input: String, form: Bool) -> (encoded: String, fields: APITraceCapturedFields)? {
        var fields: APITraceCapturedFields = [:]
        var encoded: [String] = []
        for pair in input.split(separator: "&", omittingEmptySubsequences: false) {
            if pair.isEmpty {
                encoded.append("")
                continue
            }
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let encodedName = String(parts[0])
            let encodedValue = parts.count == 2 ? String(parts[1]) : ""
            guard let name = Self.decodeParameter(encodedName),
                  let value = Self.decodeParameter(encodedValue)
            else { return nil }
            let rule = parameterRule(name)
            let sanitized = rule.apply(value)
            if rule == .replace || value != sanitized {
                encoded.append(encodedName + "=" + Self.encodeParameter(sanitized, form: form))
            } else {
                encoded.append(String(pair))
            }
            if !form {
                fields[name] = APITraceCapturedField(mode: rule.mode, values: (fields[name]?.values ?? []) + [sanitized])
            }
        }
        return (encoded.joined(separator: "&"), fields)
    }

    private func headerRule(_ name: String, custom: [String: APITraceCaptureMode]) -> Rule {
        let normalized = APITraceCredentialNames.normalize(name)
        if credentials.exceptHeaders.contains(normalized) { return .keep }
        return credentials.headers.contains(normalized) || custom[normalized] == .includes ? .replace : .inspect
    }

    private func parameterRule(_ name: String) -> Rule {
        let normalized = APITraceCredentialNames.normalize(name)
        if credentials.exceptQueryParameters.contains(normalized) { return .keep }
        return credentials.queryParameters.contains(normalized) || normalizedQueryRules[normalized] == .includes
            ? .replace : .inspect
    }

    private func sanitizeHeader(_ value: String, name: String, rule: Rule) -> String {
        guard case .inspect = rule else { return rule.apply(value) }
        switch name.lowercased() {
        case "location", "content-location", "referer":
            return sanitizeURL(URLComponents(string: value))?.url
                ?? APITraceCredentialNames.marker
        case "refresh":
            guard let delimiter = value.range(of: #";\s*url\s*=\s*"#, options: [.regularExpression, .caseInsensitive]) else {
                return Self.stripJWT(value)
            }
            let link = value[delimiter.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return Self.stripJWT(String(value[..<delimiter.upperBound]))
                + sanitizeHeader(link, name: "Location", rule: .inspect)
        default:
            return Self.stripJWT(value)
        }
    }

    private enum Rule {
        case keep
        case replace
        case inspect

        var mode: APITraceCaptureMode {
            if case .replace = self { return .includes }
            return .exact
        }

        func apply(_ value: String) -> String {
            switch self {
            case .keep: value
            case .replace: APITraceCredentialNames.marker
            case .inspect: APITraceRedactor.stripJWT(value)
            }
        }
    }

    private static func stripJWT(_ value: String) -> String {
        value.replacingOccurrences(of: APITraceCredentialNames.jwtPattern, with: "$1.$2.redacted", options: .regularExpression)
    }

    private static func decodeParameter(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    private static func encodeParameter(_ value: String, form: Bool) -> String {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: parameterCharacters) ?? ""
        return form ? encoded.replacingOccurrences(of: "%20", with: "+") : encoded
    }

    private static func normalized(
        _ rules: [String: APITraceCaptureMode],
        by normalize: (String) -> String
    ) -> [String: APITraceCaptureMode] {
        var result: [String: APITraceCaptureMode] = [:]
        for (name, mode) in rules {
            let key = normalize(name)
            if result[key] != .includes { result[key] = mode }
        }
        return result
    }

    private static let parameterCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static let cookieNamePattern = #"^\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+(?=\s*=)"#
    private static let setCookieSeparator = #",(?=\s*[!#$%&'*+\-.^_`|~0-9A-Za-z]+\s*=)"#

    public static let `default` = APITraceRedactor()
}
