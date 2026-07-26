import APITraceCore
import Foundation

final class APITraceURLProtocol: URLProtocol {
    private var sessionTask: URLSessionDataTask?
    private var passthroughSession: URLSession?

    private var configuration = APITraceURLProtocolContext.snapshot().configuration
    private var startedAt = Date()
    private var redactedURL = APITraceRedactedURL(url: "", queryItems: [:])
    private var requestPayload = APITraceRequest()
    private var endpoint = ""
    private var method = "GET"

    private var receivedResponse: HTTPURLResponse?
    private var responseBodyPrefix = Data()
    private var responseBodyBytesSeen = 0

    /// Guards the flags below: `stopLoading` runs on the client thread while the
    /// passthrough session delivers delegate callbacks on its own serial queue.
    private let stateLock = NSLock()
    private var isStopped = false
    private var didRedirect = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }

        guard APITraceURLProtocolContext.snapshot().isCapturing else {
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

        // Snapshot the active configuration once so this request is unaffected by a
        // concurrent start()/stop()/install() on another thread mid-flight.
        let configuration = APITraceURLProtocolContext.snapshot().configuration
        self.configuration = configuration
        startedAt = Date()
        method = request.httpMethod ?? "GET"
        endpoint = url.path
        redactedURL = configuration.redactor.redact(url: url)

        var requestBody: Data?
        if configuration.captureRequestBodies {
            // Reading an upload stream here consumes or blocks it before URLSession can
            // send it. Streamed bodies are therefore forwarded untouched and not captured.
            requestBody = request.httpBody
        }

        let requestForLoading = mutableRequest as URLRequest
        requestPayload = makeRequestPayload(
            from: requestForLoading,
            body: requestBody,
            redactedURL: redactedURL,
            configuration: configuration
        )

        // Per-request session with this protocol as delegate: streams data to the client
        // as it arrives, and forwards redirects and auth challenges (certificate pinning,
        // custom trust) back to the app's own session instead of swallowing them.
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        sessionConfiguration.urlCache = nil
        let existing = sessionConfiguration.protocolClasses ?? []
        sessionConfiguration.protocolClasses = existing.filter { $0 != APITraceURLProtocol.self }
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        passthroughSession = session

        sessionTask = session.dataTask(with: requestForLoading)
        sessionTask?.resume()
    }

    override func stopLoading() {
        stateLock.lock()
        isStopped = true
        stateLock.unlock()
        sessionTask?.cancel()
    }

    // MARK: - Record assembly

    private func appendRecord(response: HTTPURLResponse?, body: Data?, bodyTruncated: Bool, error: Error?) {
        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000))

        let responsePayload: APITraceResponse? = response.map { httpResponse in
            let headers = configuration.redactor.redact(
                responseHeaders: Self.normalizeHeaders(httpResponse.allHeaderFields)
            )
            let bodyCapture = Self.decodeBody(body, truncated: bodyTruncated)
            return APITraceResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                bodyText: bodyCapture.text,
                bodyBase64: bodyCapture.base64
            )
        }

        configuration.recorder.append(
            APITraceRecord(
                startedAt: startedAt,
                durationMs: durationMs,
                method: method,
                url: redactedURL.url,
                endpoint: endpoint,
                request: requestPayload,
                response: responsePayload,
                errorMessage: error.map { configuration.redactor.redact(errorMessage: $0.localizedDescription) }
            )
        )
    }

    private func makeRequestPayload(
        from request: URLRequest,
        body: Data?,
        redactedURL: APITraceRedactedURL,
        configuration: APITraceURLProtocolContext.Configuration
    ) -> APITraceRequest {
        let headers = configuration.redactor.redact(singleValueHeaders: request.allHTTPHeaderFields ?? [:])
        let cappedBody = body.map { Data($0.prefix(configuration.maxBodyBytes)) }
        let bodyCapture = Self.decodeBody(
            cappedBody,
            truncated: (body?.count ?? 0) > configuration.maxBodyBytes
        )
        return APITraceRequest(
            headers: headers,
            queryItems: redactedURL.queryItems,
            bodyText: bodyCapture.text,
            bodyBase64: bodyCapture.base64
        )
    }

    // MARK: - Helpers

    private static func normalizeHeaders(_ rawHeaders: [AnyHashable: Any]) -> APITraceHeaders {
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

    private static func decodeBody(_ data: Data?, truncated: Bool) -> (text: String?, base64: String?) {
        guard let data, !data.isEmpty else {
            return (nil, nil)
        }

        if let text = String(data: data, encoding: .utf8) {
            return (text, nil)
        }

        // A byte-limit cut can split a multi-byte UTF-8 character; drop the partial
        // trailing character instead of misclassifying the body as binary.
        if truncated {
            for trim in 1...3 where data.count > trim {
                if let text = String(data: data.dropLast(trim), encoding: .utf8) {
                    return (text, nil)
                }
            }
        }

        return (nil, data.base64EncodedString())
    }

}

// MARK: - Passthrough session delegate

extension APITraceURLProtocol: URLSessionDataDelegate {
    /// True once the loading system no longer wants callbacks (stopLoading ran or a
    /// redirect was handed back); no `client` call may happen after that.
    private var isClientDetached: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isStopped || didRedirect
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !isClientDetached else {
            completionHandler(.cancel)
            return
        }

        receivedResponse = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isClientDetached else { return }
        client?.urlProtocol(self, didLoad: data)

        guard configuration.captureResponseBodies else { return }
        responseBodyBytesSeen += data.count
        let remaining = configuration.maxBodyBytes - responseBodyPrefix.count
        if remaining > 0 {
            responseBodyPrefix.append(data.prefix(remaining))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Record this hop, then hand the redirect back to the app's loading system,
        // which cancels this load and re-dispatches the new request through the
        // protocol chain (producing a separate record for the next hop).
        appendRecord(response: response, body: nil, bodyTruncated: false, error: nil)

        stateLock.lock()
        didRedirect = true
        stateLock.unlock()

        var redirected = request
        if let mutableRedirect = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
            URLProtocol.removeProperty(forKey: APITraceURLProtocolContext.handledKey, in: mutableRedirect)
            redirected = mutableRedirect as URLRequest
        }
        client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
        completionHandler(nil)
        task.cancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Forward the challenge to the app's session so its own trust evaluation
        // (certificate pinning, custom CAs, client certificates) stays in effect.
        let sender = APITraceChallengeSender(completionHandler: completionHandler)
        let forwarded = URLAuthenticationChallenge(authenticationChallenge: challenge, sender: sender)
        client?.urlProtocol(self, didReceive: forwarded)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.finishTasksAndInvalidate()
            passthroughSession = nil
        }

        stateLock.lock()
        let stopped = isStopped
        let redirected = didRedirect
        stateLock.unlock()

        // The redirect hop was already recorded and the client re-dispatched.
        if redirected { return }

        appendRecord(
            response: receivedResponse,
            body: responseBodyPrefix,
            bodyTruncated: responseBodyBytesSeen > configuration.maxBodyBytes,
            error: error
        )

        guard !stopped else { return }

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

/// Bridges `URLProtocolClient` challenge responses back into the passthrough
/// session's completion handler.
private final class APITraceChallengeSender: NSObject, URLAuthenticationChallengeSender {
    private let completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    private let lock = NSLock()
    private var responded = false

    init(completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        self.completionHandler = completionHandler
    }

    private func respond(_ disposition: URLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
        lock.lock()
        defer { lock.unlock() }
        guard !responded else { return }
        responded = true
        completionHandler(disposition, credential)
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        respond(.useCredential, credential)
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        respond(.performDefaultHandling, nil)
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        respond(.cancelAuthenticationChallenge, nil)
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        respond(.performDefaultHandling, nil)
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        respond(.rejectProtectionSpace, nil)
    }
}
