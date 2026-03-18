# iOS Integration

## What the SDK Does

- `APITraceCore` provides the facade and exported record model.
- `APITraceDebug` installs a `URLProtocol`-based backend.
- `APITraceNoop` installs a release-safe no-op backend.

The debug backend registers a global `URLProtocol`, so it captures `URLSession` traffic once installed and started.

## Integration Steps

1. Add the Swift package from `git@github.com:ArjangConsulting/ios-network-recorder.git` or a local path.
2. Link `APITraceCore` plus the debug/noop products your build setup needs.
3. Patch app startup in the composition root, usually `App`, `AppDelegate`, or an app bootstrap object.
4. Install the correct backend.
5. Call `APITrace.start()`.
6. Add a developer-only export action.

## Minimal Bootstrap

```swift
import APITraceCore
#if DEBUG
import APITraceDebug
#else
import APITraceNoop
#endif

func configureAPITrace() {
#if DEBUG
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
#else
    APITraceNoopBootstrap.install()
#endif

    APITrace.start()
}
```

## Export Hook

Use:

```swift
let data = try APITrace.exportJSON(prettyPrinted: true)
```

Typical next step:

- write to a temporary `.json` file
- present a share sheet
- hand the file to an existing debug upload flow

## Patch Carefully

- Put bootstrap before major `URLSession` activity begins.
- If the app creates network traffic during launch, install early.
- If the app has its own diagnostics screen, add export there instead of creating a new screen.
- Keep redaction opt-in. Do not persist sensitive query items or auth headers without an explicit rule.
