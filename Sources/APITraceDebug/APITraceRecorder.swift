import APITraceCore
import Foundation

final class APITraceRecorder {
    private let lock = NSLock()
    private var buffer: [APITraceRecord] = []
    private let maxRecords: Int

    init(maxRecords: Int) {
        self.maxRecords = max(1, maxRecords)
    }

    func append(_ record: APITraceRecord) {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(record)
        if buffer.count > maxRecords {
            buffer.removeFirst(buffer.count - maxRecords)
        }
    }

    func snapshot() -> [APITraceRecord] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }
}
