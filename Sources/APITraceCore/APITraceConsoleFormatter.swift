/// Formats sanitized trace records for readable multiline console output.
public struct APITraceConsoleFormatter: Sendable {
    /// Maximum number of body characters included before a truncation marker is appended.
    public let maxBodyCharacters: Int

    public init(maxBodyCharacters: Int = 10_000) {
        precondition(maxBodyCharacters >= 0, "maxBodyCharacters must not be negative")
        self.maxBodyCharacters = maxBodyCharacters
    }

    /// Returns one readable request/response or request/failure block.
    ///
    /// The formatter operates on an `APITraceRecord`, so headers and URLs have already passed
    /// through the recorder's configured redaction policy.
    public nonisolated func format(_ record: APITraceRecord) -> String {
        let request = section(
            heading: "→ REQUEST \(record.method) \(record.url)",
            headers: record.request.headers.mapValues(\.values),
            body: bodyText(record.request.bodyText, base64: record.request.bodyBase64)
        )

        let outcome: String
        if let response = record.response {
            outcome = section(
                heading: "← RESPONSE \(response.statusCode) (\(record.durationMs)ms)",
                headers: response.headers,
                body: bodyText(response.bodyText, base64: response.bodyBase64)
            )
        } else {
            outcome = """
                ✗ FAILURE (\(record.durationMs)ms)
                  Error:
                \(indented(record.errorMessage ?? "<unknown>"))
                """
        }

        return "\(request)\n\(outcome)"
    }

    private nonisolated func section(
        heading: String,
        headers: APITraceHeaders,
        body: String
    ) -> String {
        """
        \(heading)
          Headers:
        \(formattedHeaders(headers))
          Body:
        \(indented(body))
        """
    }

    private nonisolated func formattedHeaders(_ headers: APITraceHeaders) -> String {
        guard !headers.isEmpty else { return indented("<none>") }
        let lines = headers.keys.sorted().map { name in
            "\(name): \(headers[name, default: []].joined(separator: ", "))"
        }
        return indented(lines.joined(separator: "\n"))
    }

    private nonisolated func bodyText(_ text: String?, base64: String?) -> String {
        guard let text else {
            return base64.map { "<binary body: base64, \($0.count) characters>" } ?? "<empty>"
        }
        guard text.count > maxBodyCharacters else { return text.isEmpty ? "<empty>" : text }
        return String(text.prefix(maxBodyCharacters)) + "…[truncated]"
    }

    private nonisolated func indented(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
    }
}
