# Copilot Instructions

Use `AGENTS.md` as the full repository guide. The essentials are:

- This repo is an iOS Swift Package Manager SDK for API trace capture.
- Products: `APITraceCore` (facade + models), `APITraceDebug` (URLProtocol backend), `APITraceNoop` (release-safe no-op).
- Request header and query capture is opt-in via `APITraceRedactor`.
- Run `swift test` after changes.
- Update `README.md` when public behavior or integration steps change.
- Keep the Android counterpart (`android-network-recorder`) semantically aligned for shared behavior changes.
