import Foundation
import ObjectiveC
import OSLog

/// The cookie settings of the session a captured request came from. Forwarding a request with
/// these settings lets the URL loading system send and store cookies exactly as it would with
/// capture off.
struct APITraceCookieProfile {
    /// Weak, so the registry never keeps a session's cookies alive after the session is gone.
    weak var storage: HTTPCookieStorage?
    let hadStorage: Bool
    let acceptPolicy: HTTPCookie.AcceptPolicy
    let shouldSetCookies: Bool

    init(configuration: URLSessionConfiguration) {
        storage = configuration.httpCookieStorage
        hadStorage = configuration.httpCookieStorage != nil
        acceptPolicy = configuration.httpCookieAcceptPolicy
        shouldSetCookies = configuration.httpShouldSetCookies
    }

    func matches(_ other: APITraceCookieProfile) -> Bool {
        hadStorage == other.hadStorage
            && storage === other.storage
            && acceptPolicy == other.acceptPolicy
            && shouldSetCookies == other.shouldSetCookies
    }

    /// True once the store is gone, which means every session that used it is gone too.
    var isDead: Bool { hadStorage && storage == nil }

    func apply(to configuration: URLSessionConfiguration) {
        configuration.httpCookieStorage = storage
        configuration.httpCookieAcceptPolicy = acceptPolicy
        configuration.httpShouldSetCookies = shouldSetCookies
    }
}

/// Maps a capture protocol class to the cookie settings of the configuration it was added to.
///
/// A `URLProtocol` can't see the session that started its task: `URLSessionTask` has no public
/// `session`. `protocolClasses` is the one thing a configuration carries into its session that a
/// protocol instance can read back, so `enableCapture(in:)` adds a runtime subclass of
/// ``APITraceURLProtocol`` per distinct cookie profile, and the protocol looks its own class up.
/// The base class is what `URLProtocol.registerClass` installs for `URLSession.shared`.
enum APITraceSessionProfiles {
    private static let logger = Logger(subsystem: "com.apitrace", category: "SessionProfiles")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var profiles: [ObjectIdentifier: APITraceCookieProfile] = [:]
    nonisolated(unsafe) private static var classes: [ObjectIdentifier: AnyClass] = [:]
    nonisolated(unsafe) private static var counter = 0

    static var registeredClassCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return classes.count
    }

    /// The capture class for this configuration's cookie settings. Configurations with the same
    /// settings share a class, and a class whose store has been deallocated is reused, so the
    /// number of classes stays bounded by the number of live cookie stores.
    static func captureClass(for configuration: URLSessionConfiguration) -> AnyClass {
        let profile = APITraceCookieProfile(configuration: configuration)
        lock.lock()
        defer { lock.unlock() }
        if let match = profiles.first(where: { $0.value.matches(profile) }), let captureClass = classes[match.key] {
            return captureClass
        }
        if let dead = profiles.first(where: { $0.value.isDead }), let captureClass = classes[dead.key] {
            profiles[dead.key] = profile
            return captureClass
        }
        counter += 1
        let name = "APITraceURLProtocol_Session\(counter)"
        guard let captureClass = objc_allocateClassPair(APITraceURLProtocol.self, name, 0) else {
            logger.error("Could not create \(name, privacy: .public); this session's cookies fall back to URLSession.shared's settings")
            return APITraceURLProtocol.self
        }
        objc_registerClassPair(captureClass)
        let key = ObjectIdentifier(captureClass)
        classes[key] = captureClass
        profiles[key] = profile
        logger.debug("Registered \(name, privacy: .public) for a new cookie profile")
        return captureClass
    }

    /// The cookie settings for a protocol instance's class. The base class serves
    /// `URLSession.shared`.
    static func profile(for captureClass: AnyClass?) -> APITraceCookieProfile {
        if let captureClass {
            lock.lock()
            let found = profiles[ObjectIdentifier(captureClass)]
            lock.unlock()
            if let found {
                return found
            }
        }
        return APITraceCookieProfile(configuration: URLSession.shared.configuration)
    }

    /// True for ``APITraceURLProtocol`` and every capture subclass.
    static func isCaptureClass(_ candidate: AnyClass) -> Bool {
        var current: AnyClass? = candidate
        while let type = current {
            if type == APITraceURLProtocol.self {
                return true
            }
            current = class_getSuperclass(type)
        }
        return false
    }
}
