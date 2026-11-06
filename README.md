# KomunikacjaWiejska

> [!WARNING]
> ### ⚠️ Slopware
> **Notice:** This codebase is almost entirely vibecoded. While I try my best to keep the code quality as high as I can, I've figured this fact should be clearly stated for the ones who care. Additionally, any prose beyond this point may also be AI-generated. Have a nice day >w<

A native iOS client for [zbiorkom.live](https://zbiorkom.live), built with
SwiftUI, MapKit, CoreLocation, Observation, and Swift Concurrency. There are no
third-party dependencies.

## Requirements

- **Xcode 27.2 or newer.** This project uses Xcode's JSON project format
  (`KomunikacjaWiejska.xcodeproj/project.xcproj`, `last-upgrade = 27.2`), which
  older Xcode versions cannot open.
- **iOS 26.0** deployment target (the minimum for the native Liquid Glass APIs).
- A simulator or device running iOS 26 or newer.

Run `scripts/check-toolchain.sh` or `./scripts/verify.sh` in CI before building; it fails loudly when
Xcode is older than 27.2. A complete GitHub Actions workflow is provided in `.github/workflows/ci.yml`.

## Build and test

```bash
# Run the complete verification gate (toolchain check, build, and tests)
./scripts/verify.sh

# Or run individual steps:
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
- [`docs/refactor20261106/`](docs/refactor20261106/) — active Plan 2 backlog, open decisions, and progress.
- [`docs/archive/refactor20261105/`](docs/archive/refactor20261105/) — historical refactor archive.
