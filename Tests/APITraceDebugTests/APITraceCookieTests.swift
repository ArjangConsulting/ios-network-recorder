@testable import APITraceDebug
import Foundation
import Testing

/// Capture must not change how a session handles cookies. These tests change global URL loading
/// state, so they belong to the serialized lifecycle suite.
extension APITraceURLSessionBackendTests {
    private var cookieHost: String { "127.0.0.1" }

    private func clearCookies(_ storage: HTTPCookieStorage?) {
        for cookie in storage?.cookies ?? [] { storage?.deleteCookie(cookie) }
    }

    private func cookieNames(_ storage: HTTPCookieStorage?) -> String {
        (storage?.cookies ?? []).filter { $0.domain == cookieHost }.map(\.name).sorted().joined(separator: "+")
    }

    private func seedCookie(_ storage: HTTPCookieStorage?, name: String = "sid", value: String = "abc") {
        guard let cookie = HTTPCookie(properties: [.name: name, .value: value, .domain: cookieHost, .path: "/"]) else { return }
        storage?.setCookie(cookie)
    }

    private func cookieStatus(_ session: URLSession, _ port: UInt16, _ path: String, handleCookies: Bool = true) async -> String {
        var request = URLRequest(url: URL(string: "http://\(cookieHost):\(port)\(path)")!)
        request.httpShouldHandleCookies = handleCookies
        do {
            let (_, response) = try await session.data(for: request)
            return String((response as? HTTPURLResponse)?.statusCode ?? -1)
        } catch {
            return "error"
        }
    }

    private func captureEnabled(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        APITraceDebugBootstrap.enableCapture(in: configuration)
        return configuration
    }

    /// Each scenario's observable outcome: statuses and which cookies each store ends up with.
    private func cookieCases(port: UInt16) async -> [(String, String)] {
        var rows: [(String, String)] = []
        let shared = HTTPCookieStorage.shared

        // URLSession.shared
        clearCookies(shared)
        var a = await cookieStatus(.shared, port, "/login")
        var b = await cookieStatus(.shared, port, "/me")
        rows.append(("shared: login,me", "\(a),\(b) shared=[\(cookieNames(shared))]"))

        // .default custom session
        clearCookies(shared)
        var session = URLSession(configuration: captureEnabled(.default))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("default: login,me", "\(a),\(b) shared=[\(cookieNames(shared))]"))

        // .ephemeral
        clearCookies(shared)
        var configuration = captureEnabled(.ephemeral)
        var own = configuration.httpCookieStorage
        session = URLSession(configuration: configuration)
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("ephemeral: login,me", "\(a),\(b) own=[\(cookieNames(own))] shared=[\(cookieNames(shared))]"))

        // ephemeral must not see cookies that only the shared store holds
        clearCookies(shared)
        seedCookie(shared)
        configuration = captureEnabled(.ephemeral)
        session = URLSession(configuration: configuration)
        a = await cookieStatus(session, port, "/me")
        rows.append(("ephemeral: shared-only cookie not sent", a))

        // custom store on a default configuration
        clearCookies(shared)
        own = URLSessionConfiguration.ephemeral.httpCookieStorage
        configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = own
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("custom store: login,me", "\(a),\(b) own=[\(cookieNames(own))] shared=[\(cookieNames(shared))]"))

        // nil store
        clearCookies(shared)
        seedCookie(shared)
        configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("nil store: login,me", "\(a),\(b) shared=[\(cookieNames(shared))]"))

        // httpShouldSetCookies = false
        clearCookies(shared)
        configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("shouldSetCookies=false: login,me", "\(a),\(b) shared=[\(cookieNames(shared))]"))
        clearCookies(shared)
        seedCookie(shared)
        b = await cookieStatus(session, port, "/me")
        rows.append(("shouldSetCookies=false: seeded me", b))

        // accept policy .never, own store so the shared store's policy is untouched
        clearCookies(shared)
        configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        own = configuration.httpCookieStorage
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("acceptPolicy=never (own store): login,me", "\(a),\(b) own=[\(cookieNames(own))] shared=[\(cookieNames(shared))]"))

        // accept policy .never on the shared store's configuration
        clearCookies(shared)
        let policyBefore = shared.cookieAcceptPolicy
        configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("acceptPolicy=never (default): login,me", "\(a),\(b) shared=[\(cookieNames(shared))] storePolicy=\(shared.cookieAcceptPolicy.rawValue)"))
        shared.cookieAcceptPolicy = policyBefore

        // redirect that sets a cookie mid-chain
        clearCookies(shared)
        a = await cookieStatus(.shared, port, "/redir-login")
        rows.append(("shared: redirect sets cookie", "\(a) shared=[\(cookieNames(shared))]"))
        clearCookies(shared)
        configuration = captureEnabled(.ephemeral)
        own = configuration.httpCookieStorage
        session = URLSession(configuration: configuration)
        a = await cookieStatus(session, port, "/redir-login")
        rows.append(("ephemeral: redirect sets cookie", "\(a) own=[\(cookieNames(own))] shared=[\(cookieNames(shared))]"))

        // cookie written to the store out of band, as an app does after a web view sign-in
        clearCookies(shared)
        seedCookie(shared)
        a = await cookieStatus(.shared, port, "/me")
        rows.append(("shared: out-of-band cookie", a))
        configuration = captureEnabled(.ephemeral)
        session = URLSession(configuration: configuration)
        _ = await cookieStatus(session, port, "/ping")
        seedCookie(configuration.httpCookieStorage)
        a = await cookieStatus(session, port, "/me")
        rows.append(("ephemeral: out-of-band cookie", a))

        // request-level opt-out
        clearCookies(shared)
        seedCookie(shared)
        a = await cookieStatus(.shared, port, "/me", handleCookies: false)
        b = await cookieStatus(.shared, port, "/login2", handleCookies: false)
        rows.append(("request httpShouldHandleCookies=false", "\(a),\(b) shared=[\(cookieNames(shared))]"))

        // two Set-Cookie headers
        clearCookies(shared)
        a = await cookieStatus(.shared, port, "/login2")
        rows.append(("two Set-Cookie headers", "\(a) shared=[\(cookieNames(shared))]"))

        // explicit Cookie header set by the app, no stored cookie
        clearCookies(shared)
        var request = URLRequest(url: URL(string: "http://\(cookieHost):\(port)/me")!)
        request.setValue("sid=abc", forHTTPHeaderField: "Cookie")
        let code = ((try? await URLSession.shared.data(for: request))?.1 as? HTTPURLResponse)?.statusCode ?? -1
        rows.append(("app-set Cookie header", String(code)))

        // configuration reused for two sessions with different stores, enableCapture called for each
        clearCookies(shared)
        configuration = URLSessionConfiguration.default
        let first = URLSession(configuration: captureEnabled(configuration))
        own = URLSessionConfiguration.ephemeral.httpCookieStorage
        configuration.httpCookieStorage = own
        let second = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(first, port, "/login")
        b = await cookieStatus(second, port, "/me")
        rows.append(("reused configuration, two stores", "\(a),\(b) own=[\(cookieNames(own))] shared=[\(cookieNames(shared))]"))

        // store-level accept policy
        clearCookies(shared)
        configuration = URLSessionConfiguration.ephemeral
        own = configuration.httpCookieStorage
        own?.cookieAcceptPolicy = .never
        session = URLSession(configuration: captureEnabled(configuration))
        a = await cookieStatus(session, port, "/login")
        b = await cookieStatus(session, port, "/me")
        rows.append(("store.cookieAcceptPolicy=never: login,me", "\(a),\(b) own=[\(cookieNames(own))]"))

        // redirect with a cookie already stored
        clearCookies(shared)
        seedCookie(shared, name: "pre", value: "1")
        a = await cookieStatus(.shared, port, "/redir-login")
        rows.append(("shared: redirect with stored cookie", "\(a) shared=[\(cookieNames(shared))]"))

        // parallel load over two stores
        clearCookies(shared)
        configuration = captureEnabled(.ephemeral)
        own = configuration.httpCookieStorage
        let isolated = URLSession(configuration: configuration)
        _ = await cookieStatus(.shared, port, "/login")
        let statuses = await withTaskGroup(of: String.self) { group -> [String] in
            for index in 0..<40 {
                group.addTask {
                    await self.cookieStatus(index.isMultiple(of: 2) ? .shared : isolated, port, "/me")
                }
            }
            var out: [String] = []
            for await item in group { out.append(item) }
            return out
        }
        let ok = statuses.filter { $0 == "200" }.count
        let denied = statuses.filter { $0 == "401" }.count
        rows.append(("parallel, two stores", "200x\(ok) 401x\(denied) own=[\(cookieNames(own))]"))

        clearCookies(shared)
        return rows
    }

    @Test("Capture keeps every session's cookie behaviour")
    func captureKeepsCookieBehaviour() async throws {
        let server = CookieServer()
        let port = try server.start()
        defer { server.stop() }

        let captureOff = await cookieCases(port: port)
        let backend = APITraceURLSessionBackend()
        backend.start()
        let captureOn = await cookieCases(port: port)
        backend.stop()

        #expect(captureOn.count == captureOff.count)
        for (off, on) in zip(captureOff, captureOn) {
            #expect(on.1 == off.1, "\(off.0): capture off \(off.1), capture on \(on.1)")
        }
    }

    @Test("Configurations with the same cookie settings share one capture class")
    func captureClassesAreShared() {
        _ = captureEnabled(.default)
        let before = APITraceSessionProfiles.registeredClassCount
        for _ in 0..<50 {
            _ = captureEnabled(.default)
        }
        #expect(APITraceSessionProfiles.registeredClassCount == before)

        let configuration = URLSessionConfiguration.default
        APITraceDebugBootstrap.enableCapture(in: configuration)
        APITraceDebugBootstrap.enableCapture(in: configuration)
        let captureClasses = (configuration.protocolClasses ?? []).filter { APITraceSessionProfiles.isCaptureClass($0) }
        #expect(captureClasses.count == 1)
    }

    @Test("A discarded store's capture class is reused")
    func deadStoreClassReused() {
        for _ in 0..<5 {
            autoreleasepool {
                _ = captureEnabled(.ephemeral)
            }
        }
        let before = APITraceSessionProfiles.registeredClassCount
        for _ in 0..<50 {
            autoreleasepool {
                _ = captureEnabled(.ephemeral)
            }
        }
        #expect(APITraceSessionProfiles.registeredClassCount <= before + 1)
    }
}
