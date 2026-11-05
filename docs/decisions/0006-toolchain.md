# ADR-0006 — Xcode 27.2+ and the JSON project format

**Status:** Accepted (2026-11-05) — implemented in P5-1/P5-2

## Context
`KomunikacjaWiejska.xcodeproj` uses Xcode's JSON project format
(`project.xcproj`, `last-upgrade = 27.2`) rather than the legacy
`project.pbxproj`. `xcodebuild -list` works with the installed Xcode 27.2, but
older toolchains cannot open the project.

## Decision
Keep the JSON project format and declare **Xcode 27.2+** as the minimum. Commit
a shared scheme and a toolchain check instead of relying on local user data.

## Consequences
- `scripts/check-toolchain.sh` fails loudly when Xcode is older than 27.2; CI
  must run it before building.
- `xcuserdata` is untracked and ignored; the scheme lives under
  `xcshareddata/xcschemes/`.
- Contributors wanting an older Xcode would need to regenerate a legacy project
  file, which is out of scope.
