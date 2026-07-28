import Foundation

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
        body: String?
    ) -> String {
        var lines = [
            heading,
            "  Headers:",
            formattedHeaders(headers),
        ]
        if let body {
            lines.append("  Body:")
            lines.append(indented(body))
        }
        return lines.joined(separator: "\n")
    }

    private nonisolated func formattedHeaders(_ headers: APITraceHeaders) -> String {
        guard !headers.isEmpty else { return indented("<none>") }
        let lines = headers.keys.sorted().map { name in
            "\(name): \(headers[name, default: []].joined(separator: ", "))"
        }
        return indented(lines.joined(separator: "\n"))
    }

    private nonisolated func bodyText(_ text: String?, base64: String?) -> String? {
        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let formatted = prettyPrintedJSON(text) ?? text
            guard formatted.count > maxBodyCharacters else { return formatted }
            return String(formatted.prefix(maxBodyCharacters)) + "…[truncated]"
        }

        guard let base64, !base64.isEmpty else { return nil }
        return "<binary body: base64, \(base64.count) characters>"
    }

    private nonisolated func prettyPrintedJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[",
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let formattedData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        else {
            return nil
        }
        return String(data: formattedData, encoding: .utf8)
    }

    private nonisolated func indented(_ value: String) -> String {
        value.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
    }
}
