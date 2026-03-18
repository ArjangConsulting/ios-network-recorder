# Contributing

## Development Approaches

### Standalone Development

Clone this repo directly and work on it independently:

```bash
git clone git@github.com:ArjangConsulting/ios-network-recorder.git
cd ios-network-recorder
swift test
```

### Container Repo Development

This repo is also used as a submodule in the [mobile-network-recorder](https://github.com/ArjangConsulting/mobile-network-recorder) container repo for cross-platform development:

```bash
git clone --recurse-submodules git@github.com:ArjangConsulting/mobile-network-recorder.git
cd mobile-network-recorder/ios
```

When developing via the container repo:

1. Make changes inside the `ios/` submodule directory.
2. Commit and push changes in the submodule first.
3. Then update the submodule pointer in the container repo with a separate commit.

### Validation

Run `swift test` from the repository root before committing.

### Cross-Platform Considerations

This SDK has an Android counterpart at [android-network-recorder](https://github.com/ArjangConsulting/android-network-recorder). If your changes affect:

- Capture semantics or lifecycle
- Redaction behavior
- Exported record format or JSON keys
- Bootstrap/install behavior

...consider whether the Android SDK needs a corresponding update.
