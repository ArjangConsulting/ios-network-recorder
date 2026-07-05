# CLAUDE.md

Start with `AGENTS.md`. It is the canonical repo guide.

The short version:

- This repo is the iOS SwiftPM implementation of the APITrace network recording SDK.
- Products: `APITraceCore`, `APITraceDebug`, `APITraceNoop`.
- Keep public capture behavior semantically aligned with the Android counterpart.
- Both platforms export `startedAt` as ISO 8601 with millisecond precision; the Kotlin model stores epoch ms internally but the wire format is unified.
- Update `README.md` when public API, export shape, or integration steps change.
- Validate with `swift test`.
