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
- `APITraceConsoleFormatter(maxBodyCharacters:).format(_:)`
- `APITraceRedactor(headerRules:queryItemRules:responseHeaderRules:replacement:)`
- `APITraceDebugBootstrap.install(maxRecords:redactor:maxBodyBytes:captureRequestBodies:captureResponseBodies:)`
- `APITraceDebugBootstrap.enableCapture(in:)` — opts a custom `URLSessionConfiguration` into capture (no-op variant in `APITraceNoop`)

All public types/functions are documented with Swift doc comments in `Sources/APITraceCore` and public bootstrap files.

## Readable Console Output

`APITraceConsoleFormatter` turns an already-sanitized record into an indented request and
response/failure block. It returns a string so the host app can use its preferred logger:

```swift
let formatter = APITraceConsoleFormatter(maxBodyCharacters: 10_000)

for record in APITrace.records() {
    logger.debug("\(formatter.format(record), privacy: .public)")
}
```

The formatter never accepts raw requests or responses. It formats the stored `APITraceRecord`,
so URLs and headers have already passed through the configured redaction policy. Text bodies are
truncated to `maxBodyCharacters`; binary bodies are described without printing their base64 data.

## Stored Data Format

Each record is one full exchange (request + response/failure):

```json
{
  "id": "...",
  "startedAt": "2026-03-05T03:27:10.123Z",
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
- Response headers are captured by default, except credential-bearing and redirect headers
  (`Set-Cookie`, `Set-Cookie2`, `Authorization`, `Proxy-Authenticate`, `WWW-Authenticate`,
  `Location`, `Content-Location`, `Refresh`), which are replaced with the replacement value.
  Custom `responseHeaderRules` extend these defaults. Override a default with `exact`
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
    captureRequestBodies: true,
    captureResponseBodies: true,
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
- Body capture is disabled by default because bodies are stored verbatim with no field-level
  redaction. Explicitly enable it only for endpoints whose payloads are safe to retain.
- Enabled bodies are captured as UTF-8 text when possible; otherwise base64, and truncated
  to `maxBodyBytes` (default 64 KB). Streamed request bodies are forwarded untouched and are
  not captured because consuming them could alter the upload.
- Stored URLs always omit user credentials and fragments. Query items remain opt-in.
- Auth challenges are forwarded to the app's session, so certificate pinning and custom
  trust evaluation keep working while tracing is enabled.
- Redirects are re-dispatched through the app's session; each hop produces its own record.
  Redirect headers are redacted by default because they commonly contain authorization codes.
- Error messages are sanitized: query strings in embedded URLs are stripped before storage.
- Records live in memory only; exports (`exportJSON`/`exportHAR`) still contain captured
  response data, so treat exported files as sensitive.
- Capture only happens between `APITrace.start()` and `APITrace.stop()`.

## Releases

Release Please uses the built-in `GITHUB_TOKEN`. The organization allows Actions to create
pull requests, while the workflow grants only the write permissions needed for releases.
Automatic releases stay within the current major version and increment the minor version.
An intentional major release requires an explicit `Release-As: X.0.0` commit footer.
