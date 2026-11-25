import Foundation
import OSLog

/// App overrides for built-in redaction, using the fields of a `redact` block.
public struct APITraceRedactionConfiguration: Codable, Sendable {
    public let headers: [String]
    public let queryParameters: [String]
    public let except: Exceptions

    public init(headers: [String] = [], queryParameters: [String] = [], except: Exceptions = .init()) {
        self.headers = headers
        self.queryParameters = queryParameters
        self.except = except
    }

    private enum CodingKeys: String, CodingKey {
        case headers, except
        case queryParameters = "query_parameters"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            headers: try container.decodeIfPresent([String].self, forKey: .headers) ?? [],
            queryParameters: try container.decodeIfPresent([String].self, forKey: .queryParameters) ?? [],
            except: try container.decodeIfPresent(Exceptions.self, forKey: .except) ?? .init()
        )
    }

    public struct Exceptions: Codable, Sendable {
        public let headers: [String]
        public let queryParameters: [String]

        public init(headers: [String] = [], queryParameters: [String] = []) {
            self.headers = headers
            self.queryParameters = queryParameters
        }

        private enum CodingKeys: String, CodingKey {
            case headers
            case queryParameters = "query_parameters"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                headers: try container.decodeIfPresent([String].self, forKey: .headers) ?? [],
                queryParameters: try container.decodeIfPresent([String].self, forKey: .queryParameters) ?? []
            )
        }
    }
}

/// Built-in lists and JWT pattern from moqserver's
/// `server/Sources/MoqCore/Validation/CredentialNames.swift` at `6719593`.
enum APITraceCredentialNames {
    static let headers = [
        "Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
        "X-Authorization", "X-Api-Key", "Api-Key", "X-Auth-Token",
        "X-Access-Token", "X-Refresh-Token", "X-Id-Token", "X-CSRF-Token",
        "X-XSRF-Token", "X-Amz-Security-Token", "X-Goog-Api-Key", "X-Firebase-AppCheck",
        "Ocp-Apim-Subscription-Key",
    ]
    static let queryParameters = [
        "access_token", "refresh_token", "id_token", "id_token_hint",
        "client_secret", "client_assertion", "assertion", "code_verifier",
        "device_code", "subject_token", "actor_token", "token",
        "password", "api_key", "SAMLResponse", "X-Amz-Signature",
        "X-Amz-Security-Token", "X-Goog-Signature",
    ]
    static let protectedHeaders = [
        "Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
    ]

    /// HAR-only lists from `server/Sources/MoqImport/HARImporter.swift` at the same commit.
    static let importOnlyHeaders = [
        "x-forwarded-for", "www-authenticate",
    ]
    static let importOnlyParameters = [
        "code", "state", "auth", "key",
        "sig", "signature", "client_id", "code_challenge",
        "challenge", "email", "authenticity_token", "samlrequest",
    ]

    static let jwtPattern = #"(?<![A-Za-z0-9_-])(eyJ[A-Za-z0-9_-]{4,}=*)\.(eyJ[A-Za-z0-9_-]{4,}=*)\.[A-Za-z0-9\-_.+/=]*"#
    static let marker = "[redacted]"

    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0 != "-" && $0 != "_" }
    }
}

struct APITraceCredentialPolicy: Sendable {
    let headers: Set<String>
    let queryParameters: Set<String>
    let exceptHeaders: Set<String>
    let exceptQueryParameters: Set<String>

    init(_ configuration: APITraceRedactionConfiguration) {
        let protected = Set(APITraceCredentialNames.protectedHeaders.map(APITraceCredentialNames.normalize))
        let requested = Set(configuration.except.headers.map(APITraceCredentialNames.normalize))
        if !requested.isDisjoint(with: protected) {
            Logger(subsystem: "com.apitrace", category: "Redaction").warning(
                "Ignoring redaction exception for a protected credential header"
            )
        }
        exceptHeaders = requested.subtracting(protected)
        exceptQueryParameters = Set(configuration.except.queryParameters.map(APITraceCredentialNames.normalize))
        headers = Set((APITraceCredentialNames.headers + APITraceCredentialNames.importOnlyHeaders
            + configuration.headers).map(APITraceCredentialNames.normalize)).subtracting(exceptHeaders)
        queryParameters = Set((APITraceCredentialNames.queryParameters + APITraceCredentialNames.importOnlyParameters
            + configuration.queryParameters).map(APITraceCredentialNames.normalize)).subtracting(exceptQueryParameters)
    }
}
