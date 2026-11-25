import APITraceCore
import Foundation
import Testing

@Suite("Credential redaction")
struct APITraceCredentialRedactionTests {
    private static let headers = [
        "Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
        "X-Authorization", "X-Api-Key", "Api-Key", "X-Auth-Token",
        "X-Access-Token", "X-Refresh-Token", "X-Id-Token", "X-CSRF-Token",
        "X-XSRF-Token", "X-Amz-Security-Token", "X-Goog-Api-Key", "X-Firebase-AppCheck",
        "Ocp-Apim-Subscription-Key", "x-forwarded-for", "www-authenticate",
    ]
    private static let parameters = [
        "access_token", "refresh_token", "id_token", "id_token_hint",
        "client_secret", "client_assertion", "assertion", "code_verifier",
        "device_code", "subject_token", "actor_token", "token",
        "password", "api_key", "SAMLResponse", "X-Amz-Signature",
        "X-Amz-Security-Token", "X-Goog-Signature", "code", "state",
        "auth", "key", "sig", "signature",
        "client_id", "code_challenge", "challenge", "email",
        "authenticity_token", "samlrequest",
    ]

    @Test("Every credential header is redacted in both directions", arguments: headers)
    func credentialHeader(name: String) {
        let values = ["example-secret", "another-example-secret"]
        let redactor = APITraceRedactor.default
        let expected = ["[redacted]", "[redacted]"]
        #expect(redactor.redact(headers: [name: values])[name] == .init(mode: .includes, values: expected))
        #expect(redactor.redact(responseHeaders: [name: values])[name] == expected)
    }

    @Test("Every credential parameter is redacted in URL, HAR queryString, form and nested JSON", arguments: parameters)
    func credentialParameter(name: String) throws {
        let redactor = APITraceRedactor.default
        let url = try #require(URL(string: "https://api.example.test/?\(name)=example-secret"))
        let captured = redactor.redact(url: url)
        #expect(captured.url == "https://api.example.test/?\(name)=%5Bredacted%5D")

        let record = APITraceRecord(
            durationMs: 0, method: "GET", url: captured.url, endpoint: "/",
            request: .init(queryItems: captured.queryItems)
        )
        let archive = try #require(JSONSerialization.jsonObject(with: APITrace.exportHAR([record])) as? [String: Any])
        let log = try #require(archive["log"] as? [String: Any])
        let entries = try #require(log["entries"] as? [[String: Any]])
        let request = try #require(entries.first?["request"] as? [String: Any])
        #expect(request["queryString"] as? [[String: String]] == [["name": name, "value": "[redacted]"]])

        let form = redactor.redact(
            body: Data("\(name)=example-secret&author=pilot".utf8), contentType: "application/x-www-form-urlencoded"
        )
        #expect(form == "\(name)=%5Bredacted%5D&author=pilot")

        let body = #"{"items":[{"\#(name)":{"nested":"example-secret"},"author":"pilot"}]}"#
        let json = redactor.redact(body: Data(body.utf8), contentType: "application/problem+json; charset=utf-8")
        let jsonData = Data(try #require(json).utf8)
        let object = try #require(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        #expect(object["items"] as? [[String: String]] == [[name: "[redacted]", "author": "pilot"]])
    }

    @Test("Exact normalized names, shared configuration, and JWT rules")
    func configurablePolicy() throws {
        let configuration = try JSONDecoder().decode(APITraceRedactionConfiguration.self, from: Data(
            #"{"headers":["X-App-Device"],"query_parameters":["device_ref"],"except":{"headers":["X-Csrf-Token","AUTHORIZATION","proxy_authorization","cookie","set_cookie"],"query_parameters":["token","email"]}}"#.utf8
        ))
        let redactor = APITraceRedactor(redact: configuration)
        let jwt = "eyJhbGci.eyJzdWIi.example-signature"
        let trimmed = "eyJhbGci.eyJzdWIi.redacted"
        let ordinary = "https://monkeys.eyewear.example.test/"
        let headers = redactor.redact(singleValueHeaders: [
            "Authorization": jwt, "Proxy-Authorization": jwt, "Cookie": jwt, "Set-Cookie": jwt,
            "X_CSRF_token": jwt, "X-APP_DEVICE": "example-secret", "X_API_key": "example-secret",
            "X-Session-Ref": ordinary, "X-JWT": "Bearer \(jwt)",
        ])
        for name in ["Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie", "X-APP_DEVICE", "X_API_key"] {
            #expect(headers[name]?.values == ["[redacted]"])
        }
        #expect(headers["X_CSRF_token"]?.values == [jwt])
        #expect(headers["X-Session-Ref"]?.values == [ordinary])
        #expect(headers["X-JWT"]?.values == ["Bearer \(trimmed)"])

        let url = try #require(URL(string: "https://api.example.test/?api%5Fkey=secret&apiKey=secret&API-KEY=secret&deviceRef=secret&token=\(jwt)&ref=\(jwt)&keyword=term&sort_key=date&author=pilot"))
        let query = redactor.redact(url: url).queryItems
        for name in ["api_key", "apiKey", "API-KEY", "deviceRef"] {
            #expect(query[name]?.values == ["[redacted]"])
        }
        #expect(query["token"]?.values == [jwt])
        #expect(query["ref"]?.values == [trimmed])
        #expect(query["keyword"]?.values == ["term"])
        #expect(query["sort_key"]?.values == ["date"])
        #expect(query["author"]?.values == ["pilot"])
        let redirect = redactor.redact(responseHeaders: ["Location": ["/next?state=secret&token=\(jwt)&ref=\(jwt)#secret"]])
        #expect(redirect["Location"] == ["/next?state=%5Bredacted%5D&token=\(jwt)&ref=\(trimmed)"])
        let jwtInAuthority = redactor.redact(responseHeaders: ["Location": ["https://\(jwt).example.test/"]])
        #expect(jwtInAuthority["Location"] == ["https://\(trimmed)"])

        let form = "ref=\(jwt)&token=\(jwt)&device-ref=secret&email=user%40example.com"
        #expect(redactor.redact(body: Data(form.utf8), contentType: "application/x-www-form-urlencoded")
            == "ref=\(trimmed)&token=\(jwt)&device-ref=%5Bredacted%5D&email=user%40example.com")
        let body = #"{"items":[{"token":"\#(jwt)","ref":"\#(jwt)","device_ref":42}, "\#(jwt)"]}"#
        #expect(redactor.redact(body: Data(body.utf8), contentType: "application/json")
            == #"{"items":[{"device_ref":"[redacted]","ref":"\#(trimmed)","token":"\#(jwt)"},"\#(trimmed)"]}"#)
    }

    @Test("Uninspectable body data never falls back to raw text or base64")
    func rejectsUninspectableBody() {
        let redactor = APITraceRedactor.default
        #expect(redactor.redact(body: Data(#"{"token":"example-secret""#.utf8), contentType: "application/json") == nil)
        #expect(redactor.redact(body: Data("token=example-secret".utf8), contentType: "application/octet-stream") == nil)
        #expect(redactor.redact(body: Data("bad%zz=example-secret".utf8), contentType: "application/x-www-form-urlencoded") == nil)
    }
}
