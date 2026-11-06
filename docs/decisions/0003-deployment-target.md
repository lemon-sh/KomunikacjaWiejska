# ADR-0003 — Deployment target lowered to iOS 26 (Decision 1D6)

**Status:** Accepted and implemented (2026-11-05, 1P5-4)

## Context
The project shipped with `IPHONEOS_DEPLOYMENT_TARGET = 27.2`, which excludes
almost every device in circulation. All APIs the app actually uses
(`.buttonStyle(.glass)`, `glassEffect`, `GlassEffectContainer`, `MapCompass`,
`onMapCameraChange`) are available from iOS 26.

## Decision
The developer chose to **lower the minimum to the glass-feature minimum (iOS
26.0)** rather than keep 27.2.

## Consequences
- `IPHONEOS_DEPLOYMENT_TARGET` is `26.0` for the app and test targets.
- No `ultraThinMaterial` fallbacks are needed: all glass APIs remain available.
- The project still requires **Xcode 27.2+** because of the JSON
  `project.xcproj` format; `scripts/check-toolchain.sh` enforces that.
- Releases should be smoke-tested on an iOS 26 runtime; the current development
  simulator runs iOS 27.2.
