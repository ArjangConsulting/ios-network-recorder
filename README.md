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

Captured requests keep their session's cookie behaviour: the session's own `httpCookieStorage`,
`httpCookieAcceptPolicy` and `httpShouldSetCookies` apply, redirect hops included, so a
cookie-based sign-in works the same with capture on. `enableCapture(in:)` reads those settings
when it is called, so call it last, just before creating the session, and again if you change
them and reuse the configuration.

## Write a HAR File For Test Harnesses

UI test harnesses can collect a run's traffic without app-specific export code. Launch the app
with `APITRACE_HAR_FILE=1` in its environment and `APITraceDebugBootstrap.install()` also writes
the captured history to `APITraceHARFile.defaultURL` (`apitrace.har` in the app's temporary
directory) after every recorded exchange. `clear()` rewrites it empty.

- The file lives in the app's data container, so a harness can copy it: on a simulator with
  `xcrun simctl get_app_container <device> <bundle-id> data` (`tmp/apitrace.har` under it), on a
  device with `xcrun devicectl device copy from --domain-type appDataContainer` for
  development-signed builds.
- The temporary directory is not backed up and not shown in the Files app; the system may
  purge it while the app isn't running, so copy the file right after the scenario.
- Pass `harFileURL:` to `install` (or to `APITraceURLSessionBackend`) to choose another
  location, or `nil` to never write one. Writes are coalesced and best effort; a failed write
  is logged (subsystem `com.apitrace`, category `HARFile`) and never affects the app's own requests.
- `APITraceNoop` never writes a file.

## Public API Surface

- `APITrace.install(_:)`
- `APITrace.start()` — enables capture; no requests are recorded before this is called.
- `APITrace.stop()` — disables capture; already-buffered records are kept, but no new requests are recorded until `start()` is called again.
- `APITrace.clear()`
- `APITrace.records()`
- `APITrace.exportJSON(prettyPrinted:)`
- `APITrace.exportHAR(prettyPrinted:)`
- `APITrace.exportHAR(_:prettyPrinted:)` (export a given list of records)
- `APITraceHARFile.environmentKey`, `APITraceHARFile.defaultURL`, `APITraceHARFile.url(environment:)`
- `APITraceConsoleFormatter(maxBodyCharacters:).format(_:)`
- `APITraceRedactor(headerRules:queryItemRules:responseHeaderRules:replacement:redact:)`
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
pretty-printed when they contain a JSON object or array, then truncated to `maxBodyCharacters`.
Empty and whitespace-only bodies are omitted. Binary bodies are described without printing their
base64 data.

## Stored Data Format

Each record is one full exchange (request + response/failure):

```json
{
  "id": "...",
  "startedAt": "2026-03-05T03:27:10.123Z",
  "durationMs": 84,
  "method": "GET",
  "url": "https://api.example.test/v1/users?page=1&token=%5Bredacted%5D",
  "endpoint": "/v1/users",
  "request": {
    "headers": {
      "Authorization": {
        "mode": "includes",
        "values": ["[redacted]"]
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
        "values": ["[redacted]"]
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

### Credential Redaction

Both request and response headers and all URL query parameters are captured. Built-in
credential names and HAR-import extras keep only presence: `[redacted]` in values and
`%5Bredacted%5D` in URLs and form data. Names match exactly after lowercasing and removing
`-` and `_`; for example, `api_key`, `apiKey` and `API-KEY` match, while `sort_key` does
not. A JWT under an unlisted name keeps its header and payload but loses its signature.
Cookie headers are redacted; HAR cookie entries retain the name and a placeholder value.

Pass extra names and exceptions to `APITraceRedactor(redact:)`. The configuration is
`Codable` and mirrors the `redact` block: `headers`, `query_parameters`, and `except`
with the same two lists. Query names also apply to form fields and nested JSON keys.
Exceptions keep the original value, including a JWT. Attempts to except
`Authorization`, `Proxy-Authorization`, `Cookie`, or `Set-Cookie` are ignored and
log a warning. Use exceptions only for values safe to share.

```swift
APITraceDebugBootstrap.install(
    captureRequestBodies: true,
    captureResponseBodies: true,
    redactor: APITraceRedactor(
        redact: APITraceRedactionConfiguration(
            headers: ["X-App-Device"],
            queryParameters: ["device_ref"],
            except: .init(headers: ["X-CSRF-Token"], queryParameters: ["token"])
        )
    )
)
```

Existing `headerRules`, `queryItemRules`, and `responseHeaderRules` can still add
redactions with `.includes`. An `.exact` rule no longer overrides the credential policy;
use `except` for an explicit override. The legacy `replacement` argument is accepted for
source compatibility; capture always writes the HAR-compatible marker.

## Notes

- Uses `URLProtocol` to intercept HTTP/HTTPS via `URLSession`. Global registration only
  reaches `URLSession.shared`; use `enableCapture(in:)` for custom configurations.
- Body capture is off by default. When enabled, only complete UTF-8 JSON and form-encoded
  payloads within `maxBodyBytes` (default 64 KB) are kept, after redaction. Unsupported,
  malformed, and partial bodies are omitted. URLSession can present uploads as streams;
  only requests that reach the recorder with an in-memory body can be captured.
- Stored URLs omit user information and fragments. Query fields are sanitized in both
  the request URL and `queryString`, including in captured redirect URL headers.
- Auth challenges are forwarded to the app's session, so certificate pinning and custom
  trust evaluation keep working while tracing is enabled.
- Redirects are re-dispatched through the app's session; each hop produces its own record.
- Transport failures use a fixed message rather than storing free-form network errors.
- Treat exports as sensitive: unlisted secrets, excepted values, and JWT payload claims can
  remain. Records passed directly to `exportHAR(_:prettyPrinted:)` must already be sanitized.
- Capture only happens between `APITrace.start()` and `APITrace.stop()`.

## Releases

Release Please uses the built-in `GITHUB_TOKEN`. The organization allows Actions to create
pull requests, while the workflow grants only the write permissions needed for releases.
Automatic releases stay within the current major version and increment the minor version.
An intentional major release requires an explicit `Release-As: X.0.0` commit footer.

### Capture completeness in HAR exports

New response records carry optional `bodyCapture` metadata. HAR exports preserve it
as `response._capture`: `capturedByteCount` counts sanitized bytes retained, and
`observedByteCount` counts received bytes. `isTruncated` flags an exceeded byte limit;
`isComplete` is false when a nonempty body could not be kept. `content.size` reflects
observed bytes for retained bodies. Entry `_error` indicates a transport failure. Consumers must not
replay captures marked incomplete as successful responses. Missing metadata on older
or Android exports means unknown completeness, not a guarantee of completeness.
These additive fields do not change HAR 1.2 compatibility.
