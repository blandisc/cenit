# The package layer

Almost none of Cénit's real work happens in the app target. The persistence, the physiology math,
the training domain, the importers and the entire visual language live in eight SwiftPM packages
under `Packages/`, and the iOS app is a thin shell that wires them to screens.

That split is not decoration. It is what makes the fast loop possible: `swift build && swift test`
inside a package needs no Xcode project, no simulator, no signing and no HealthKit, so the math can
be changed and proven in seconds. It is also what makes the packages reusable — each is a
self-contained library with an explicit dependency list.

This document is the reference for that layer. For the database schema those packages persist, see
[DATA_MODEL.md](DATA_MODEL.md); for the physiology, [ANALYTICS.md](ANALYTICS.md).

> Cénit is not a medical device. Every derived value — heart rate, variability, recovery, effort,
> sleep, temperature — is a documented approximation, not a clinical measurement.

---

## What every package has in common

Eight manifests, and they agree on five things. Treat these as invariants: a change that breaks one
should be deliberate and argued, not incidental.

**Every product is a static library with exactly one target.** All eight declare
`.library(name:, type: .static, targets: [...])`. The static linkage is what lets the app's unit-test
bundle depend on a package with `link: false` — it compiles against the module while taking the
symbols from the host app, instead of linking a second copy and failing on duplicate code.

**Every target enables strict concurrency.** Library, executable and test targets alike carry
`swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]`. There are no other Swift
settings anywhere in the layer.

**Every package declares more than one platform.** The minimum pairs differ (see the table below),
but no package is iOS-only. That is the mechanism that keeps UI frameworks out: a package that
imported UIKit unconditionally would stop building for macOS, and the macOS build is what CI runs.

**No package re-exports another.** There is not one `@_exported import` in the repository, packages
or app. A file that needs a type says which module it comes from.

**Only two third-party dependencies exist in the whole layer**, and both are local-only libraries
that make no network calls of their own.

| Dependency | Requirement | Resolved | Used by | For |
| --- | --- | --- | --- | --- |
| GRDB.swift | `from: "6.0.0"` | 6.29.3 | `CenitStore` (and `StrandImport` transitively) | SQLite persistence and migrations |
| ZIPFoundation | `from: "0.9.0"` | 0.9.20 | `StrandImport` | Reading the user's own Health export archive |

A third dependency, swift-syntax, exists only under `Tools/DesignCensus` — a developer executable
that is never linked into a shipped target.

---

## The graph

```
BiometricStreams ──┬──────────────────► StrandAnalytics
StrandModels ──────┘

BiometricStreams ──┐
StrandModels ──────┤
StrandTraining ────┼──► CenitStore ──┐
GRDB ──────────────┘                 ├──► StrandImport
StrandTraining ──────────────────────┤
ZIPFoundation ───────────────────────┘

CenitDesign        (no package dependencies)
CenitEnsenanza     (no package dependencies)
```

Five of the eight have **no inbound package edges at all**: `BiometricStreams`, `StrandModels`,
`StrandTraining`, `CenitDesign` and `CenitEnsenanza`. Two chains grow out of that floor — the
analytics chain and the persistence chain — and they meet only in the app.

The direction is the rule. `CenitStore` and `StrandAnalytics` may depend on `BiometricStreams`;
`BiometricStreams` may never depend on them. Four packages sit at the top and are imported by
nobody else in the layer: `StrandAnalytics`, `StrandImport`, `CenitDesign` and `CenitEnsenanza` are
consumed only by the app, the widgets and the watch.

### Platform minimums

| Package | iOS | macOS | watchOS |
| --- | --- | --- | --- |
| `BiometricStreams`, `StrandModels`, `CenitEnsenanza`, `CenitStore`, `StrandAnalytics`, `StrandImport` | 16 | 13 | — |
| `StrandTraining` | 16 | 13 | 10 |
| `CenitDesign` | 17 | 14 | 10 |

`CenitDesign` carries the highest floor because it uses SwiftUI APIs that only exist there.
`StrandTraining` gained watchOS so the watch companion can speak the real domain types over the
wire rather than a parallel set of copies.

---

## The packages

### `BiometricStreams` — the vocabulary

Two files, 224 lines, zero dependencies of any kind. This is the floor of the graph, and its
manifest says so.

It defines the neutral shapes a decoded biometric sample takes — `HRSample`, `RRInterval`,
`SkinTempSample`, `RespSample`, `GravitySample`, and the `Streams` batch that carries arrays of
each. All are `Equatable, Codable, Sendable`, and every `ts` is unix wall-clock seconds.

Only `hr` and `rr` have a live write path today; the other three shapes are documented as dormant,
with no producer feeding them.

The second file is `ParsedValue`, a small `Codable` enum over `int`, `double`, `string`, `intArray`,
`bool` and `null`. Its encoder writes the **bare JSON scalar** rather than a tagged union, and its
decoder tries `Bool` before `Int` — that order is load-bearing, because JSON `true` would otherwise
decode as an integer.

Two test files cover the codec round-trips, the decode ordering and the struct defaults.

### `StrandModels` — the row shapes

Three files, 209 lines, no dependencies. A leaf, deliberately: it holds the value types that both
the store and the analytics layer need to name, so neither has to depend on the other.

- `DailyMetric` — the nineteen-field day row, with every metric nullable.
- `CachedSleepSession` — one night, with its stage breakdown kept as a verbatim JSON string.
- `AppleDaily` — the Apple-Health daily aggregate row.
- `DietMealStatus` — the tri-state adherence value.
- `DayKey` — the day-key contract described in [DATA_MODEL.md](DATA_MODEL.md#conventions).

One design detail is worth calling out. `DailyMetric.with(...)` takes a `FieldUpdate` per field
rather than an optional, so `.set(nil)` (clear this column) is distinguishable from omission (leave
it alone). With plain optionals across nineteen fields those two intents collapse into one, and the
distinction is exactly what the store's monotonic upsert depends on.

Two of its columns hold a raw confidence *string* rather than an enum, because the enum lives in
`StrandAnalytics` — which sits above this package.

### `StrandTraining` — the strength domain

Twenty-four files, about 3 400 lines, Foundation-only and dependency-free. No GRDB, no UI: GRDB
conformance for these types is added by extension inside `CenitStore`, which is what keeps the
domain usable on the watch.

The core file defines the vocabulary of a workout: routines and folders, the weekly schedule, the
prescribed `RoutineSet` and the performed `SetEntry`, sessions, personal records, rest
configuration, and `StrengthSessionSnapshot` — the crash-durable picture of a session in progress.

Around it sit small, single-purpose pure modules: one-rep-max estimation, plate math, progression
state, deload policy, program calendars, week bucketing, rest statistics, RIR-to-RPE conversion,
muscle inference, routine classification, CSV export, and a reconciler that fuses the sets logged on
the watch with the ones logged on the phone.

The exercise catalog ships as a bundled resource, not as database rows: two zlib-compressed JSON
files holding 873 exercises and a matching Spanish overlay, decompressed at load. A third resource
directory that once held baked thumbnails now ships **empty apart from its README** — the catalog
moved to a source with no media. That emptiness is load-bearing: the code only derives a remote
media URL for ids present in the baked-stills set, so an empty set means no URL is ever derived.

Twenty-two test files, about 2 200 lines, covering the snapshot round-trip, the reconciler, CSV
formats, program calendars, progression and deload boundaries, and catalog integrity.

### `CenitStore` — persistence

Sixteen files, about 4 300 lines. Depends on `BiometricStreams`, `StrandModels`, `StrandTraining`
and GRDB.

`CenitStore` is an actor wrapping a GRDB writer, with two selectable backends and forty-three
registered migrations. Its full surface — the schema, the migration ledger, the write and read
semantics, the source-partition model — is documented in [DATA_MODEL.md](DATA_MODEL.md); this entry
covers only its shape as a package.

The single largest file is the strength store, which alone exposes about sixty public methods:
routines and folders, the weekly schedule, programs, session save and update and delete and restore,
per-session pulse capture, notes, and six personal-record accessors. The migration file is the
second largest. The remaining files each own one surface — the metric caches, the long-format metric
series, diet, experiments, cursors, the in-progress session, and a one-transaction dashboard read.

Two compressed JSON resources ride along, used by exactly one migration; if they are absent that
migration is a no-op rather than a failure.

Twenty-one test files, about 5 500 lines, dominated by the migration and strength suites. All run
against an in-memory store.

### `StrandAnalytics` — the physiology

Ninety-five files, about 17 500 lines. Depends on `BiometricStreams` and `StrandModels` and nothing
else — **no GRDB, no database, no I/O.** Every engine is a pure function from values to values,
which is what makes the whole package testable without a device.

The engines group into families: baselines and deviation; the morning readiness verdict; variability
and autonomic analysis; effort and load; heart-rate zones and recovery; sleep staging and
regularity; stress; statistical inference; insights and single-subject experiments; source fusion
and arbitration; fitness age; and the pure strength math the training screens read.

A hundred and twenty-three test files, about 15 300 lines. Several recognizable families are worth
knowing about: **oracle tests** check an engine against hand-computed references; **boundary tests**
pin behavior exactly at a threshold; **copy guards** assert that the words shown next to a number
stay honest; and **invariance tests** assert that a value does not change when it must not.

One guard exists in this package, and it is the only conditional compilation outside the design
system: a `#if canImport(Darwin)` around localized-string lookup, so the package still builds on
Linux — where the localization overload does not exist — and its math tests still run there.

### `StrandImport` — bringing data in

Fourteen files, about 4 000 lines. Depends on `CenitStore`, `StrandTraining` and ZIPFoundation.

It handles four import shapes:

- **The Apple Health export**, accepted as a `.zip`, an unpacked folder, or the raw XML, streamed
  rather than loaded, and folded into civil days by a day aggregator. A UTF-8 scrubber sits in front
  of the parser because real exports contain malformed sequences.
- **Strength CSV** from two third-party trackers plus Cénit's own export format.
- **A prescribed diet plan** and **a workout program**, both parse-only against a versioned schema
  tag, producing warnings rather than silently dropping fields.
- **Sleep category samples**, with an encoder and a decoder that are exact inverses of each other.

ZIPFoundation is used in read mode only; nothing here writes an archive. One small module,
the third-party-workout deduplicator, is pure and imports nothing — it operates on a minimal data
transfer object so it can be tested in isolation.

Seventeen test files, about 2 800 lines, driven by six bundled fixtures: a sample export XML and
five CSV files covering both third-party formats and a Cénit round trip.

### `CenitDesign` — the visual system

Two hundred and two files, about 53 000 lines: by a wide margin the largest package, and the only
one that imports SwiftUI. It has **no package dependencies at all**, including on the domain
packages whose screens it dresses — its components take primitives, never domain types.

It holds the tokens (color, type, spacing, radius, motion, elevation), the glass recipes and theme
resolution, the chart vocabulary, the training-screen components, and several screen-scale
composites that the design system owns outright rather than leaving to the app.

Its resources are four Space Grotesk font faces with their license, and a Metal shader as **source
text**. Both choices are forced by SwiftPM: a package cannot declare app fonts, so the faces are
registered with CoreText at runtime; and the toolchain will not compile a target's Metal file, so
the shader ships as `.msl` and is compiled at run time. That one path then works identically from
`swift build` and from Xcode.

The package also carries a second, product-less target: an executable that regenerates the design
tokens and two design documents. Continuous integration re-runs it and fails if the output differs
from what is committed, which is what keeps the generated documentation from drifting.

Ninety-two test files, about 11 900 lines. The distinctive families here are **contrast and
accessibility gates**, **snapshot tests**, **theme-resolution tests** across light and dark, and
**token-drift gates** that assert every catalog entry still points at a file that exists.

### `CenitEnsenanza` — what the app teaches

Nine files, 756 lines, Foundation-only and dependency-free, so it runs in the fast loop and on
Linux.

It is a declarative registry of the app's teachable features: for each one, which tab it belongs to,
what it requires before it can be shown, and which teaching pieces exist for it — an empty state, a
tip, a milestone, a help section, a release note, or a gesture with its button equivalent.

Two deliberate constraints shape it. The tab enumeration is **hand-mirrored** from the design
system's rather than imported, because this package cannot import SwiftUI and still build on Linux.
And requirements are declarative only: the registry describes what a feature needs and evaluates
nothing.

Looking up an unknown identifier traps rather than returning nil. That is intentional — the
identifier set is closed and checked by a test, so a miss is a programming error, not a runtime
condition.

---

## Depending on a package

Inside this repository, packages reference each other by relative path:

```swift
dependencies: [
    .package(path: "../BiometricStreams"),
]
```

The app does the same through `project.yml`, which declares seven of the eight by local path.
`StrandModels` is **not** declared there — it arrives transitively through `CenitStore` and
`StrandAnalytics`, and adding it explicitly would be redundant rather than harmful.

Which targets link what:

| Target | Packages linked |
| --- | --- |
| `Cenit` (app) | All seven declared packages |
| `CenitWatch` | `CenitDesign`, `StrandTraining` — no GRDB on the wrist |
| `CenitWidgets` | `CenitDesign` only |
| `CenitUnitTests` | `BiometricStreams`, `CenitStore`, `StrandAnalytics`, `StrandTraining`, each with `link: false` |
| `CenitUITests` | None |

To vendor a package into another project, copy its directory and depend on it by path or URL. Only
`CenitStore` and `StrandImport` pull anything external. The analytics and training packages have no
dependencies beyond the repository's own leaves, so they lift out cleanly.

---

## Cross-platform discipline

The rule is short: **package code may not import a UI or hardware framework unconditionally.**
`import CoreBluetooth` appears nowhere in the layer, and neither do HealthKit, WatchKit, ActivityKit
or WidgetKit — those belong to the app targets.

SwiftUI is imported by 172 files, every one of them inside `CenitDesign`, and none of them guarded —
correctly, since SwiftUI exists on all three platforms that package declares.

UIKit and AppKit are a different matter. Every one of the eight files that imports UIKit, and both
files that import AppKit, sits behind a `canImport` guard, and several narrow further to `os(iOS)`
for genuinely iOS-only behavior — the pan gesture recognizer behind chart scrubbing, haptics, and
the Metal-backed hero view. Seven other packages contain **zero** conditional compilation of any
kind.

The one exception to "guards live in the design system" is the localization shim in
`StrandAnalytics` described above.

When you do need a platform-specific implementation, the shape is:

```swift
#if canImport(UIKit)
import UIKit
// iOS/watchOS implementation
#elseif canImport(AppKit)
import AppKit
// macOS implementation
#endif
```

Test code is held to a looser standard: thirteen design-system test files import AppKit unguarded,
which is fine because those suites are macOS-hosted by construction.

---

## Running the tests

Every package is testable on its own, from its own directory:

```bash
cd Packages/StrandAnalytics && swift build && swift test
```

To run one case or one method:

```bash
swift test --filter <TestCaseOrMethod>
```

Continuous integration builds and tests seven of the eight packages in a matrix, choosing the runner
by what the package actually needs. `BiometricStreams`, `StrandAnalytics` and `CenitEnsenanza` run
on Linux, which is the strongest possible proof that they carry no Apple-framework dependency.
`StrandTraining`, `CenitStore` and `StrandImport` need macOS for compression. `CenitDesign` needs
the newest macOS image for its SwiftUI APIs, and additionally cross-compiles for watchOS and iOS
simulators — a compile-only check that catches a token or component that silently stopped building
for the watch.

`StrandModels` is not in that matrix; it is exercised transitively.

One practical note: the design system's contrast tests resolve colors explicitly in light mode, but
a Mac running in dark mode has been known to change what a color resolves to. If those tests fail
locally and pass in CI, check the appearance setting before the code. Swift Testing reports failures
as `✘ Suite`, unlike the rest of the suite, which uses XCTest — worth knowing when scraping a log.
