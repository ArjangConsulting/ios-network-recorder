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

## Public API Surface

- `APITrace.install(_:)`
- `APITrace.start()`
- `APITrace.stop()`
- `APITrace.clear()`
- `APITrace.records()`
- `APITrace.exportJSON(prettyPrinted:)`
- `APITrace.exportHAR(prettyPrinted:)`
- `APITraceRedactor(headerRules:queryItemRules:replacement:)`

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

### Query Behavior

- Query items are opt-in via `queryItemRules`.
- Only configured query items remain in the stored `url`.
- Use `includes` for sensitive items such as `token` when the value should not be persisted.

## Example Configuration

```swift
APITraceDebugBootstrap.install(
    maxRecords: 500,
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

- Uses `URLProtocol` to intercept HTTP/HTTPS via `URLSession`.
- Bodies are captured as UTF-8 text when possible; otherwise base64.
