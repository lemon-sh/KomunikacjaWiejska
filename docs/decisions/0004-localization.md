# ADR-0004 — Localization scope (Decision D3)

**Status:** Accepted (2026-11-05) — implemented in P4-1

## Context
The UI started with Polish literals mixed with English enum labels and a few
English model strings. The app targets Polish transit networks, but App Store
distribution and non-Polish-speaking residents make an English UI desirable.

## Decision
Ship **Polish and English**. Polish is the primary product language; English is a
full translation. Development language remains `en`, and both `en` and `pl` are
declared as supported localizations.

All user-facing copy moves to `Resources/Localizable.xcstrings` with semantic
keys (for example `map.loading.initial`). Identifiers such as
`MapMode.rawValue` remain stable English strings and are never rendered.
`RouteType.displayName` moves to `Extensions/RouteType+UI.swift`, keeping the
model layer locale- and UI-free.

## Consequences
- Adding copy requires a catalog entry for both languages.
- `String(localized:)` is used for parameterized copy; format strings keep
  placeholders (`%@`, `%lld`).
- Tests assert stable raw values and that both localizations are bundled, not
  exact translated copy.
