# AGENTS.md

This repository contains the iOS Swift Package Manager implementation of the APITrace network recording SDK.

This file is the canonical agent guide for the repo.

## Scope

- Swift package structure, API surface, testing, and doc updates for the iOS APITrace SDK.
- For the Android counterpart, see `github.com/ArjangConsulting/android-network-recorder`.
- For cross-platform orchestration, see `github.com/ArjangConsulting/mobile-network-recorder`.

## Repo Map

- `Package.swift`: Swift package definition and products
- `Sources/APITraceCore`: public facade, models, and redaction
- `Sources/APITraceDebug`: URLProtocol-based capture backend
- `Sources/APITraceNoop`: release-safe no-op bootstrap
- `Tests/APITraceCoreTests`: current unit tests
- `README.md`: iOS integration guide

## Working Rules

- Treat `APITraceCore` as the stable Swift-facing contract.
- Prefer additive public API changes. Do not rename public symbols or JSON keys casually.
- `APITraceDebug` captures traffic by registering a global `URLProtocol`, so startup timing matters.
- `APITraceNoop` should remain safe to install in non-debug contexts.
- Keep request metadata capture opt-in through `APITraceRedactor`.
- If you change exported JSON behavior, consider the Android counterpart before finalizing. Both platforms export `startedAt` as ISO 8601 with millisecond precision — keep the wire format identical.
- When public behavior or integration changes, update `README.md`.
- This repo ships an SDK, not a sample app. Avoid app-specific assumptions in code or docs.

## Validation

- Run `swift test` from the repository root.
- Add or update Swift tests when changing redaction, exported models, or lifecycle behavior.

## Testing Expectations

- Keep or expand Swift tests when changing core redaction or record modeling behavior.

## Skills

- Use `.codex/skills/apitrace-integration/SKILL.md` for host-app integration guidance.
