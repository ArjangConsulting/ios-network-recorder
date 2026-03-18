import Foundation

/// Backend abstraction for collecting API trace exchanges.
public protocol APITraceBackend: AnyObject {
    func start()
    func stop()
    func clear()
    func records() -> [APITraceRecord]
}

/// Release-safe backend that records nothing.
public final class APITraceNoopBackend: APITraceBackend {
    public init() {}

    public func start() {}
    public func stop() {}
    public func clear() {}
    public func records() -> [APITraceRecord] { [] }
}
