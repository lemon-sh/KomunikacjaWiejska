# KomunikacjaWiejska

A native iOS client for [zbiorkom.live](https://zbiorkom.live), built with
SwiftUI, MapKit, CoreLocation, Observation, and Swift Concurrency. There are no
third-party dependencies.

## Requirements

- **Xcode 27.2 or newer.** This project uses Xcode's JSON project format
  (`KomunikacjaWiejska.xcodeproj/project.xcproj`, `last-upgrade = 27.2`), which
  older Xcode versions cannot open.
- **iOS 26.0** deployment target (the minimum for the native Liquid Glass APIs).
- A simulator or device running iOS 26 or newer.

Run `scripts/check-toolchain.sh` in CI before building; it fails loudly when
Xcode is older than 27.2.

## Build and test

```bash
# Build
xcodebuild -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# Test (the suite is hermetic; it never opens a socket)
xcodebuild test -project KomunikacjaWiejska.xcodeproj \
  -scheme KomunikacjaWiejska \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

## Documentation

- [`AGENTS.md`](AGENTS.md) — engineering guidelines and documentation index.
- [`docs/architecture.md`](docs/architecture.md) — state flow, map pipeline,
  performance strategy.
- [`docs/api.md`](docs/api.md) — API and positional tuple reference.
- [`docs/cities.md`](docs/cities.md) — bundled city catalog.
- [`docs/decisions.md`](docs/decisions.md) — architecture decision register and ADR index.
- [`docs/archive/refactor20261105/`](docs/archive/refactor20261105/) — historical refactor archive.
