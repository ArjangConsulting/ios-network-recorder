import APITraceCore
import Foundation

final class APITraceURLProtocol: URLProtocol {
    private var sessionTask: URLSessionDataTask?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }

        if URLProtocol.property(forKey: APITraceURLProtocolContext.handledKey, in: request) != nil {
            return false
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest,
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        URLProtocol.setProperty(true, forKey: APITraceURLProtocolContext.handledKey, in: mutableRequest)
        let requestForLoading = mutableRequest as URLRequest

        let startedAt = Date()
        let redactedURL = APITraceURLProtocolContext.redactor.redact(url: url)
        let requestPayload = makeRequestPayload(from: requestForLoading, redactedURL: redactedURL)

        let session = APITraceURLProtocol.makePassthroughSession()
        sessionTask = session.dataTask(with: requestForLoading) { [weak self] data, response, error in
            guard let self else { return }

            if let response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }

            if let data {
                self.client?.urlProtocol(self, didLoad: data)
            }

            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
            let method = requestForLoading.httpMethod ?? "GET"
            let endpoint = url.path

            if let error {
                APITraceURLProtocolContext.recorder.append(
                    APITraceRecord(
                        startedAt: startedAt,
                        durationMs: durationMs,
                        method: method,
                        url: redactedURL.url,
                        endpoint: endpoint,
                        request: requestPayload,
                        response: nil,
                        errorMessage: error.localizedDescription
                    )
                )
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                let httpResponse = response as? HTTPURLResponse
                APITraceURLProtocolContext.recorder.append(
                    APITraceRecord(
                        startedAt: startedAt,
                        durationMs: durationMs,
                        method: method,
                        url: redactedURL.url,
                        endpoint: endpoint,
                        request: requestPayload,
                        response: self.makeResponsePayload(from: httpResponse, body: data),
                        errorMessage: nil
                    )
                )
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        sessionTask?.resume()
    }

    override func stopLoading() {
        sessionTask?.cancel()
    }

    private func makeRequestPayload(from request: URLRequest, redactedURL: APITraceRedactedURL) -> APITraceRequest {
        let headers = APITraceURLProtocolContext.redactor.redact(singleValueHeaders: request.allHTTPHeaderFields ?? [:])
        let bodyCapture = decodeBody(request.httpBody)
        return APITraceRequest(
            headers: headers,
            queryItems: redactedURL.queryItems,
            bodyText: bodyCapture.text,
            bodyBase64: bodyCapture.base64
        )
    }

    private func makeResponsePayload(from response: HTTPURLResponse?, body: Data?) -> APITraceResponse? {
        guard let response else { return nil }

        let headers = normalizeHeaders(response.allHeaderFields)
        let bodyCapture = decodeBody(body)

        return APITraceResponse(
            statusCode: response.statusCode,
            headers: headers,
            bodyText: bodyCapture.text,
            bodyBase64: bodyCapture.base64
        )
    }

    private func normalizeHeaders(_ rawHeaders: [AnyHashable: Any]) -> APITraceHeaders {
        var output: APITraceHeaders = [:]
        output.reserveCapacity(rawHeaders.count)

        for (rawName, rawValue) in rawHeaders {
            let name = String(describing: rawName)

            if let values = rawValue as? [String] {
                output[name] = values
            } else if let value = rawValue as? String {
                output[name] = [value]
            } else {
                output[name] = [String(describing: rawValue)]
            }
        }

        return output
    }

    private func decodeBody(_ data: Data?) -> (text: String?, base64: String?) {
        guard let data, !data.isEmpty else {
            return (nil, nil)
        }

        if let text = String(data: data, encoding: .utf8) {
            return (text, nil)
        }

        return (nil, data.base64EncodedString())
    }

    private static func makePassthroughSession() -> URLSession {
        let config = URLSessionConfiguration.default
        let existing = config.protocolClasses ?? []
        config.protocolClasses = existing.filter { $0 != APITraceURLProtocol.self }
        return URLSession(configuration: config)
    }
}
