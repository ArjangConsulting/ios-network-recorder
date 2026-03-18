---
name: apitrace-integration
description: Integrate the APITrace iOS network recorder into an iOS app. Use when asked to add sanitized request/response capture, debug-only tracing, or trace export/share flows in a host project.
---

# APITrace Integration Skill (iOS)

Use this skill when an app team wants to add the iOS network recording feature into their project.

This skill is for host app integration. It is not the SDK maintenance guide.

## Use when

- adding API trace capture to an iOS app
- wiring a debug-only export/share flow for captured traffic
- integrating with moqserver ingestion or any other tool that consumes exported traces

## Resolve Up Front

- dependency strategy: local path, vendored source, or Git package URL
- real network stack in the app: `URLSession` or wrappers around it
- developer surface for export: debug screen, share sheet, hidden action, file export, or upload flow

## Workflow

1. Inspect where the host app creates its main network clients or sessions.
2. Choose how the SDK will be added. Read `references/dependency-strategies.md` if needed.
3. Add `APITraceCore` plus `APITraceDebug`/`APITraceNoop` so release behavior stays safe.
4. Install the bootstrap before the app's main network clients are created.
5. Start capture during app startup.
6. Configure an explicit redaction allowlist. Request capture is opt-in by design.
7. Add a developer-only export surface using `APITrace.exportJSON(prettyPrinted:)`.
8. Run one real request and inspect the exported payload for redaction correctness.
9. Update the host project's docs or debug menu labeling if the feature is discoverable by developers.

## Platform References

- iOS integration: `references/ios.md`
- Rollout checklist: `references/host-checklist.md`
- Dependency choices: `references/dependency-strategies.md`

## Guardrails

- Keep release builds on the no-op path unless the user explicitly wants production capture.
- Do not capture all request headers or query items by default.
- Instrument the app's real network path, not a new unused client.
- Preserve existing auth, retries, caching, logging, and certificate pinning behavior.
- If the app already has a debug menu or diagnostics screen, extend it instead of adding a second developer surface.
- Do not invent a backend upload protocol. Export JSON and connect it to the app's existing share or upload flow.

## Completion Output

When finishing the task in a host repo, report:

- where bootstrap/install happens
- which client/session path is actually instrumented
- which headers and query items are allowlisted
- how a developer exports traces
- what was validated and what is still manual
