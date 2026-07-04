import Foundation

/// Minimal loopback-only HTTP/1.1 server used for deterministic capture tests
/// without any network or third-party dependency.
final class LoopbackHTTPServer {
    enum ServerError: Error {
        case socketFailed
        case bindFailed
        case listenFailed
    }

    private let responseBody: String
    private var listenSocket: Int32 = -1
    private let queue = DispatchQueue(label: "com.apitrace.tests.loopback-http-server")

    init(responseBody: String = "ok") {
        self.responseBody = responseBody
    }

    /// Starts listening on an OS-assigned ephemeral port and returns the port number.
    func start() throws -> UInt16 {
        listenSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard listenSocket >= 0 else { throw ServerError.socketFailed }

        var reuse: Int32 = 1
        setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(listenSocket, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw ServerError.bindFailed }

        var actualAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &actualAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                _ = getsockname(listenSocket, sockaddrPointer, &len)
            }
        }

        guard listen(listenSocket, 8) == 0 else { throw ServerError.listenFailed }

        queue.async { [weak self] in
            self?.acceptLoop()
        }

        return actualAddr.sin_port.bigEndian
    }

    private func acceptLoop() {
        while true {
            let clientSocket = accept(listenSocket, nil, nil)
            if clientSocket < 0 { break }
            handle(clientSocket: clientSocket)
        }
    }

    private func handle(clientSocket: Int32) {
        defer { close(clientSocket) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        _ = recv(clientSocket, &buffer, buffer.count, 0)

        let body = responseBody
        let response = """
        HTTP/1.1 200 OK\r
        Content-Length: \(body.utf8.count)\r
        Content-Type: text/plain\r
        Connection: close\r
        \r
        \(body)
        """
        let bytes = Array(response.utf8)
        bytes.withUnsafeBufferPointer { pointer in
            _ = send(clientSocket, pointer.baseAddress, pointer.count, 0)
        }
    }

    func stop() {
        if listenSocket >= 0 {
            close(listenSocket)
            listenSocket = -1
        }
    }
}
