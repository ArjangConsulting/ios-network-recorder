import Foundation

/// Loopback HTTP server for the cookie tests: `/login` and `/login2` set cookies, `/me` answers
/// 401 without `sid=abc`, and `/redir-login` sets a cookie on a redirect to `/me`.
final class CookieServer: @unchecked Sendable {
    struct Seen {
        let path: String
        let headers: [String: String]
    }

    private var listenSocket: Int32 = -1
    private let queue = DispatchQueue(label: "apitrace.tests.cookie-server", attributes: .concurrent)
    private let lock = NSLock()
    private var seenRequests: [Seen] = []

    var seen: [Seen] {
        lock.lock()
        defer { lock.unlock() }
        return seenRequests
    }

    func start() throws -> UInt16 {
        listenSocket = socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var actual = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(listenSocket, $0, &len)
            }
        }
        listen(listenSocket, 16)
        let socketToAccept = listenSocket
        queue.async { [weak self] in
            while true {
                let client = accept(socketToAccept, nil, nil)
                if client < 0 { break }
                self?.queue.async { self?.handle(client) }
            }
        }
        return actual.sin_port.bigEndian
    }

    func stop() {
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 32 * 1024)
        let received = recv(client, &buffer, buffer.count, 0)
        guard received > 0 else { return }
        let text = String(decoding: buffer[0..<received], as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let path = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        lock.lock()
        seenRequests.append(Seen(path: path, headers: headers))
        lock.unlock()

        let cookie = headers["cookie"] ?? ""
        var status = "200 OK"
        var extra: [String] = []
        var body = "ok"
        switch path {
        case "/login":
            extra = ["Set-Cookie: sid=abc; Path=/"]
        case "/login2":
            extra = ["Set-Cookie: sid=abc; Path=/", "Set-Cookie: theme=dark; Path=/"]
        case "/me":
            if !cookie.contains("sid=abc") {
                status = "401 Unauthorized"
                body = "no cookie"
            }
        case "/redir-login":
            status = "302 Found"
            extra = ["Set-Cookie: sid=abc; Path=/", "Location: /me"]
            body = ""
        case "/echo":
            body = headers.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")
        default:
            break
        }
        var out = ["HTTP/1.1 \(status)", "Content-Length: \(body.utf8.count)", "Content-Type: text/plain", "Connection: close"]
        out.append(contentsOf: extra)
        let response = out.joined(separator: "\r\n") + "\r\n\r\n" + body
        let bytes = Array(response.utf8)
        bytes.withUnsafeBufferPointer { _ = send(client, $0.baseAddress, $0.count, 0) }
    }
}
