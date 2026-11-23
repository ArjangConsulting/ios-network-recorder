import APITraceCore
import Foundation

final class APITraceRecorder {
    private let lock = NSLock()
    private var buffer: [APITraceRecord] = []
    private let maxRecords: Int
    private var onChange: (() -> Void)?

    init(maxRecords: Int) {
        self.maxRecords = max(1, maxRecords)
    }

    /// Called after every append or clear, outside the recorder's lock.
    func setOnChange(_ handler: (() -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        onChange = handler
    }

    func append(_ record: APITraceRecord) {
        lock.lock()
        buffer.append(record)
        if buffer.count > maxRecords {
            buffer.removeFirst(buffer.count - maxRecords)
        }
        let handler = onChange
        lock.unlock()
        handler?()
    }

    func snapshot() -> [APITraceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        buffer.removeAll(keepingCapacity: true)
        let handler = onChange
        lock.unlock()
        handler?()
    }
}
