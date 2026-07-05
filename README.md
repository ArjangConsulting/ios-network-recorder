# APITraceSDK (iOS)

Debug-focused API interception starter package for SwiftPM.

## Package Products

- `APITraceCore`: facade + data models (`APITrace`, `APITraceRecord`, `APITraceRedactor`)
- `APITraceDebug`: URLSession capture backend and debug bootstrap
- `APITraceNoop`: release-safe no-op bootstrap

## Install

1. Add the Swift package:
   - Git URL: `git@github.com:ArjangConsulting/ios-network-recorder.git`
   - Or local path if developing alongside the container repo
2. Add products to your app target:
   - Always: `APITraceCore`
   - Debug config: `APITraceDebug`
   - Release config: `APITraceNoop`

## Integrate In App Startup

```swift
import APITraceCore
#if DEBUG
import APITraceDebug
#else
import APITraceNoop
#endif

func configureTracing() {
#if DEBUG
    APITraceDebugBootstrap.install(maxRecords: 500)
#else
    APITraceNoopBootstrap.install()
#endif
    APITrace.start()
}
```

### Custom URLSession Configurations

Global registration only reaches `URLSession.shared`. Sessions built from their own
`URLSessionConfiguration` (including Alamofire's) must be opted in before the session
is created:

```swift
let configuration = URLSessionConfiguration.default
APITraceDebugBootstrap.enableCapture(in: configuration) // no-op in APITraceNoop
let session = URLSession(configuration: configuration)
```

## Public API Surface

- `APITrace.install(_:)`
- `APITrace.start()` — enables capture; no requests are recorded before this is called.
- `APITrace.stop()` — disables capture; already-buffered records are kept, but no new requests are recorded until `start()` is called again.
- `APITrace.clear()`
- `APITrace.records()`
- `APITrace.exportJSON(prettyPrinted:)`
- `APITrace.exportHAR(prettyPrinted:)`
- `APITraceRedactor(headerRules:queryItemRules:responseHeaderRules:replacement:)`
- `APITraceDebugBootstrap.install(maxRecords:redactor:maxBodyBytes:captureRequestBodies:captureResponseBodies:)`
- `APITraceDebugBootstrap.enableCapture(in:)` — opts a custom `URLSessionConfiguration` into capture (no-op variant in `APITraceNoop`)

All public types/functions are documented with Swift doc comments in `Sources/APITraceCore` and public bootstrap files.

## Stored Data Format

Each record is one full exchange (request + response/failure):

```json
{
  "id": "...",
  "startedAt": "2026-03-05T03:27:10Z",
  "durationMs": 84,
  "method": "GET",
  "url": "https://api.example.com/v1/users?page=1&token=%3Cmocked%3E",
  "endpoint": "/v1/users",
  "request": {
    "headers": {
      "Authorization": {
        "mode": "includes",
        "values": ["<mocked>"]
      },
      "X-Client-Build": {
        "mode": "exact",
        "values": ["1234"]
      }
    },
    "queryItems": {
      "page": {
        "mode": "exact",
        "values": ["1"]
      },
      "token": {
        "mode": "includes",
        "values": ["<mocked>"]
      }
    },
    "bodyText": null,
    "bodyBase64": null
  },
  "response": {
    "statusCode": 200,
    "headers": {
      "Content-Type": ["application/json"]
    },
    "bodyText": "{\"ok\":true}",
    "bodyBase64": null
  },
  "errorMessage": null
}
```

### Header Behavior

- Request headers are opt-in via `headerRules`.
- `exact` preserves the original value.
- `includes` keeps only presence semantics and stores the configured replacement value.
- Response headers are captured by default, except credential-bearing headers
  (`Set-Cookie`, `Set-Cookie2`, `Authorization`, `Proxy-Authenticate`, `WWW-Authenticate`),
  which are replaced with the replacement value. Override via `responseHeaderRules`
  (`exact` opts a default back in; `includes` redacts additional headers).

### Query Behavior

- Query items are opt-in via `queryItemRules`.
- Only configured query items remain in the stored `url`.
- Use `includes` for sensitive items such as `token` when the value should not be persisted.

## Example Configuration

```swift
APITraceDebugBootstrap.install(
    maxRecords: 500,
    maxBodyBytes: 64 * 1024,
    redactor: APITraceRedactor(
        headerRules: [
            "Authorization": .includes,
            "X-Client-Build": .exact,
        ],
        queryItemRules: [
            "page": .exact,
            "token": .includes,
        ]
    )
)
```

## Notes

- Uses `URLProtocol` to intercept HTTP/HTTPS via `URLSession`. Global registration only
  reaches `URLSession.shared`; use `enableCapture(in:)` for custom configurations.
- Bodies are captured as UTF-8 text when possible; otherwise base64. Request and response
  body capture is truncated to `maxBodyBytes` (default 64 KB) to bound memory usage, and
  can be disabled entirely with `captureRequestBodies: false` / `captureResponseBodies: false`.
  Bodies are stored verbatim — there is no field-level body redaction, so disable body
  capture for endpoints that exchange credentials if that is a concern.
- Streamed request bodies are buffered in full so they can be forwarded; very large
  uploads are captured only up to `maxBodyBytes` but still transit memory once.
- Auth challenges are forwarded to the app's session, so certificate pinning and custom
  trust evaluation keep working while tracing is enabled.
- Redirects are re-dispatched through the app's session; each hop produces its own record,
  and HAR export surfaces the `Location` header as `redirectURL`.
- Error messages are sanitized: query strings in embedded URLs are stripped before storage.
- Records live in memory only; exports (`exportJSON`/`exportHAR`) still contain captured
  response data, so treat exported files as sensitive.
- Capture only happens between `APITrace.start()` and `APITrace.stop()`.
