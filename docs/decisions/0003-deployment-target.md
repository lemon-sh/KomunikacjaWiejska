# ADR-0003 — Deployment target lowered to iOS 26 (Decision D6)

**Status:** Accepted (2026-11-05) — implementation pending (refactor plan P5-4)

## Context
The project shipped with `IPHONEOS_DEPLOYMENT_TARGET = 27.2`, which excludes
almost every device in circulation. All APIs the app actually uses
(`.buttonStyle(.glass)`, `glassEffect`, `GlassEffectContainer`, `MapCompass`,
`onMapCameraChange`) are available from iOS 26.

## Decision
The developer chose to **lower the minimum to the glass-feature minimum (iOS 26.0)**
rather than keep 27.2.

## Consequences
- The project-level build setting `IPHONEOS_DEPLOYMENT_TARGET` changes to
  `26.0` in `KomunikacjaWiejska.xcodeproj/project.xcproj` (tracked as P5-4).
- No `ultraThinMaterial` fallbacks are needed: all glass APIs remain available.
- CI/builds must target the lowest supported runtime (iOS 26.0). A loud failure
  on incompatible Xcode versions is planned alongside P5-2.
