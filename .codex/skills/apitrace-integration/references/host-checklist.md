# Host App Checklist

Use this checklist after integration.

## Wiring

- The app includes `APITraceCore` plus `APITraceDebug` and `APITraceNoop` variants.
- Bootstrap runs in app startup or the main network composition root.
- The real `URLSession` path is instrumented.
- Capture starts after install.

## Safety

- Release builds stay on the no-op path.
- Redaction rules are explicit and minimal.
- Sensitive headers, tokens, cookies, and session identifiers are not stored unless the user explicitly asked for them.

## Developer Experience

- A developer can export traces without using the debugger.
- The export surface is clearly debug-only or internal.
- The output format is JSON from `APITrace.exportJSON(prettyPrinted:)`, not a custom format.

## Validation

- One successful request was captured.
- One failure case was checked if practical.
- Exported output was inspected for expected headers, query items, body capture, and redaction.
- Any platform-specific limitations were documented in the final report.
