import APITraceCore
import Foundation

enum APITraceURLProtocolContext {
    static let handledKey = "com.apitrace.handled"

    static var recorder: APITraceRecorder = APITraceRecorder(maxRecords: 500)
    static var redactor: APITraceRedactor = .default

    static func configure(recorder: APITraceRecorder, redactor: APITraceRedactor) {
        self.recorder = recorder
        self.redactor = redactor
    }
}
