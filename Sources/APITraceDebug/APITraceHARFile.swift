import APITraceCore
import Foundation

/// Opt-in export of the captured history to a HAR file, so a test harness can copy a run's
/// traffic off a simulator or device without app-specific export code.
public enum APITraceHARFile {
    /// Launch-environment key that turns HAR file export on. Accepted values: `1`, `true`, `yes`.
    public static let environmentKey = "APITRACE_HAR_FILE"

    /// `apitrace.har` in the app's temporary directory. It lives inside the app's data
    /// container, is not backed up and is not shown in the Files app.
    public static var defaultURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("apitrace.har")
    }

    /// ``defaultURL`` when `environment` asks for HAR file export, otherwise `nil`.
    public static func urlIfRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        guard let value = environment[environmentKey]?.lowercased(),
              ["1", "true", "yes"].contains(value)
        else { return nil }
        return defaultURL
    }
}

/// Rewrites the HAR file after changes, coalescing bursts into one write on a serial queue.
final class APITraceHARFileWriter {
    private let url: URL
    private let snapshot: () -> [APITraceRecord]
    private let queue = DispatchQueue(label: "com.apitrace.har-file-writer", qos: .utility)
    private let lock = NSLock()
    private var writeScheduled = false

    init(url: URL, snapshot: @escaping () -> [APITraceRecord]) {
        self.url = url
        self.snapshot = snapshot
    }

    func recordsChanged() {
        lock.lock()
        let alreadyScheduled = writeScheduled
        writeScheduled = true
        lock.unlock()
        guard !alreadyScheduled else { return }

        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.writeScheduled = false
            self.lock.unlock()
            self.write()
        }
    }

    func flush() {
        queue.sync {}
    }

    private func write() {
        do {
            let data = try APITrace.exportHAR(snapshot(), prettyPrinted: false)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Export is best effort: a failed write must never affect the app's own traffic.
        }
    }
}
