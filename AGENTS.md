# AGENTS.md

**KomunikacjaWiejska** is a native iOS client for [zbiorkom.live](https://zbiorkom.live).

## 1. Project Purpose & Scope

`KomunikacjaWiejska` is an iOS application built with pure Apple technologies (`SwiftUI`, `MapKit`, `CoreLocation`, `Observation`, Swift Concurrency) bringing Polish public transit tracking to Apple devices.

- **Primary Web Source:** [zbiorkom.live](https://zbiorkom.live)
- **Primary API Server:** `https://api.zbiorkom.live/api6-open` (OpenAPI 3.1)
- **Toolchain:** Xcode **27.2+** (JSON `project.xcproj` format), iOS **26.0**
  deployment target, Swift 6 language mode. See [`README.md`](README.md) and
  run `scripts/check-toolchain.sh` before building.

## 2. Core Documentation Index

Always refer to the dedicated guides in [`docs/`](docs) for deep technical specifications:

1. [**Architecture & Design Guide** (`docs/architecture.md`)](docs/architecture.md)
   - Architectural principles (SwiftUI + MapKit, zero third-party dependencies).
   - `@Observable` state flow and camera lifecycle (`MapViewModel`).
   - UI component hierarchy and file map.
   - Roadmap for future milestones (live vehicle positions, departure boards, trip polylines).

2. [**API Specification & Positional Tuple Reference** (`docs/api.md`)](docs/api.md)
   - Complete technical reference for `https://api.zbiorkom.live/api6-open`.
   - Index-by-index breakdown of `StopTuple`, `RouteTuple`, and `EntranceTuple` unkeyed arrays.
   - Coordinate order conventions (`[longitude, latitude]`).
   - Millisecond epoch time and error handling schemas.

3. [**Cities & Transit Networks Catalog** (`docs/cities.md`)](docs/cities.md)
   - Table of all 66 supported Polish cities and metropolitan networks.
   - City IDs, default coordinates, and search aliases.

4. [**Architecture Decisions** (`docs/decisions.md`)](docs/decisions.md)
   - Central index, executive summaries, and contribution guide for Architecture Decision Records (ADRs).
   - Links to individual records in [`docs/decisions/`](docs/decisions/).

5. [**Refactor Plan 2 Archive** (`docs/archive/refactor20261106/`)](docs/archive/refactor20261106/)
   - Completed Plan 2 backlog, decisions register (2D1–2D8), and verification status records.

6. [**Historical Refactor Archive** (`docs/archive/refactor20261105/`)](docs/archive/refactor20261105/)
   - Archived initial refactor plan (1P0–1P5, 1D1–1D8) and completion status records.

## 3. Engineering Guidelines for Future Agents

- **Zero Non-Apple Dependencies:** Prefer native Apple frameworks (`MapKit` over Google Maps/MapLibre, `URLSession` over Alamofire, `Color` & SF Symbols over custom icon packs).
- **Strictly native Liquid Glass behavior:** NEVER fall back to re-implementing native behavior. If requested functionality is impossible to achieve with native APIs, refuse and inform the developer. Examples of unwanted behavior include:
   - DON'T re-implement Liquid Glass button animations, DO use .buttonStyle(.glass)
   - DON'T create a custom MapKit compass. DO inform the developer that it's impossible for the UIKit button to have animations.
- **Modern Swift Patterns:**
  - Swift 6 language mode: avoid Combine (`AnyCancellable`, `ObservableObject`, `@Published`). Use `@Observable` and `Task`.
  - Use `async`/`await` for all asynchronous networking and actor isolation (`ZbiorkomAPIClient`).
  - Indentation: 4 spaces.
  - Safe code: Avoid force unwrapping (`!`) and force casting (`as!`).
  - Cross-actor value types are explicitly `nonisolated`; do not silence isolation diagnostics with `@preconcurrency` without a comment explaining the exact diagnostic and removal condition.
- **Localization & Accessibility:**
  - User-facing copy lives in `KomunikacjaWiejska/Resources/Localizable.xcstrings` (Polish + English). Do not add literal UI strings in views.
  - Keep identifiers (`MapMode.rawValue`, API IDs) locale-independent; use `displayName` for UI.
  - Icon-only controls need an accessibility label; marker/badge contents should combine into one element.
- **Refactor & Decision Namespacing:**
  - All refactor phases, tasks, and decision records must be namespaced by refactor iteration: `<refactor>P<phase>-<task>` (e.g. `1P2-3`, `2P1-6`, or `2P1` for the whole phase) and `<refactor>D<decision>` (e.g. `1D1`, `2D1`).
  - Code comments and architecture documentation must always use this namespaced format to ensure cross-references remain traceable across refactor cycles.
- **Testing:**
  - Use Swift `Testing` (`import Testing`, `@Suite`, `@Test`, `#expect`) in [`KomunikacjaWiejskaTests`](file:///Users/lemon/Documents/coding/KomunikacjaWiejska/KomunikacjaWiejskaTests/KomunikacjaWiejskaTests.swift).
  - Tests must be hermetic: inject `StopsProviding` stubs and `MockURLProtocol`; never hit the production API.
- **Tooling Awareness:**
  - When running within Xcode: use `xcode-tools` (`BuildProject`, `RunAllTests`, `XcodeRead`, `XcodeWrite`) instead of shell commands like `ls` or `find` to minimize user approval prompts.
