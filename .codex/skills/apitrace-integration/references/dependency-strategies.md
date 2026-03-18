# Dependency Strategies

Use the smallest viable dependency strategy for the host project.

## iOS

Preferred order:

1. Git Swift package dependency from `git@github.com:ArjangConsulting/ios-network-recorder.git`
2. Local Swift package path when developing alongside the container repo
3. Vendored source only if the project cannot consume Swift packages cleanly

The products are:

- `APITraceCore`
- `APITraceDebug`
- `APITraceNoop`

## Choose Based On Context

- If the host repo is a monorepo or adjacent local repo setup, prefer local path.
- If multiple apps need the feature, prefer the Git package URL.
- Do not fabricate package coordinates that do not exist. Use the Git URL or local path.
