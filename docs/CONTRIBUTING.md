# Contributing

This is the working guide for changing Cénit: where code belongs, what the gates enforce, how to add
the three things people most often add, and what a change has to satisfy before it merges.

Read [ARCHITECTURE.md](ARCHITECTURE.md) before any structural change, and
[BUILD.md](BUILD.md) for the toolchain and the verification command. This document assumes both.

---

## Five rules that get a change rejected

These are not style preferences. Each is enforced by something that will fail your build, and each
exists because breaking it once cost real damage.

**1. Offline only.** No server, no account, no telemetry, no network call. The app's privacy claim is
that it has no reachable network path at all, and that claim is only as strong as the next change.
See [PRIVACY_SECURITY.md](PRIVACY_SECURITY.md) for the evidence a reviewer will check against.

**2. The design system is the law.** Screens use tokens and components from `CenitDesign` and nothing
else — no raw hex, no literal font sizes, no ad-hoc spacing, no one-off card. If a token is missing,
add it to `CenitDesign` with a preview; do not inline it. The enforcement contract lives in
[design-system/CONTRATO.md](design-system/CONTRATO.md) and the visual point of view in
[design-system/DESIGN.md](design-system/DESIGN.md).

**3. Transparent math.** Every derived physiological value is a documented approximation of a
published method. A new one needs the citation, a test, and honest hedging in the copy. No black
boxes and no clinical claims — Cénit is not a medical device.

**4. The schema only grows forward.** Never edit the shipped migration, and never reuse an
identifier the installed ledger already carries: a database on a phone would skip it in silence and
fall behind with no visible error. Add the next version and a test case, and route every column
addition through the idempotent helper rather than a raw alter.

**5. One concern per pull request.** Do not commit generated files (the Xcode project, build output),
and do not fold an unrelated cleanup into a feature.

---

## Where code belongs

The single most expensive class of defect measured in this repository is writing a second version of
something that already exists. Before writing code, inventory what you will reuse: which components,
which helpers, which engine. If you cannot name them, you have not read enough yet.

The second question is which layer the code belongs in. The rule of thumb: **the more the change is
about numbers or storage, the deeper into `Packages/` it goes, and the more it must be covered by a
test that needs no app and no device.**

| The change is about | It belongs in | Proven by |
| --- | --- | --- |
| The shape of a decoded sample | `BiometricStreams` | A package test |
| A row type both storage and math must name | `CenitModels` | A package test |
| A table, a column, a query | `CenitStore` | A migration test against an in-memory store |
| A physiological computation | `CenitAnalytics` | A package test with a hand-computed reference |
| Sets, reps, progression, routines | `CenitTraining` | A package test |
| Parsing a file the user supplies | `CenitImport` | A package test over a fixture |
| A token, a component, a chart | `CenitDesign` | A package test plus a preview |
| A screen, navigation, a HealthKit call | `Cenit/` and `CenitApp/` | The app's unit tests |

If you find yourself computing a physiological value inside a view, the code is in the wrong layer.
Move it down until it can be tested without a simulator.

### Keeping the packages platform-neutral

Every package targets at least two platforms, and continuous integration builds three of them on
Linux. That is what keeps UI and hardware frameworks out of the packages. Package code must not
import UIKit, AppKit, CoreBluetooth, HealthKit or WidgetKit unconditionally.

When a platform-specific implementation is genuinely needed:

```swift
#if canImport(UIKit)
import UIKit
// iOS and watchOS
#elseif canImport(AppKit)
import AppKit
// macOS
#endif
```

Today every such guard in the layer lives in `CenitDesign`, plus one localization shim in
`CenitAnalytics`. Adding a guard anywhere else deserves a sentence in the pull request explaining
why.

Do not use `@_exported import`. There is not one in the repository, and a file should say which
module a type comes from.

---

## Repository layout

| Path | What lives there |
| --- | --- |
| `Packages/` | The eight cross-platform packages that do the real work. See [LIBRARY.md](LIBRARY.md). |
| `Cenit/` | The app layer: screens, data plumbing, onboarding, media, system glue, Live Activity. |
| `CenitApp/` | The iOS shell: app entry, the HealthKit bridge, the Info property list and entitlements. |
| `CenitShared/` | Code compiled into more than one target: the app group, and the watch-to-phone wire contract. |
| `CenitWidgets/` | The widget extension and the rest Live Activity. |
| `CenitWatch/` | The watch companion. |
| `CenitUnitTests/`, `CenitUITests/` | App-layer tests and the screenshot harness. |
| `Tools/` | Gates, linters, codegen and the verification script. |
| `docs/` | This documentation, the design system, decisions and specifications. |
| `.github/workflows/` | The six continuous-integration workflows. |

`Cenit.xcodeproj` is generated by XcodeGen from `project.yml` and is gitignored. Regenerate it after
any file addition or removal.

---

## Verifying a change

One command, before you finish anything that touches Swift:

```bash
Tools/verify.sh
```

It picks the work from what you changed: the linters always, then the touched packages, then an
unsigned app build if the app layer moved. [BUILD.md](BUILD.md) documents every mode, what "touched"
means, and the machine hygiene that keeps a full build from taking the Mac down.

Two things to know that surprise people:

- Auto mode does **not** build the app for a change confined to the watch app or to `Packages/`.
- `quick` runs linters only and deliberately does not record a completed verification.

The design-drift linter runs in two flavors. Diff-scoped rules check the files you changed. Ratchet
rules scan whole directory roots against a committed baseline, so pre-existing debt in a file you did
not touch can fail your run. That is intended: the baseline may only ever go down. A separate gate
proves the rules and roots are identical in the pre-commit hook, in `verify.sh` and in continuous
integration, so "green locally, red in CI" cannot happen quietly.

---

## Working inside the design system

### Use a token, or add one

Color, type, spacing, radius, motion and elevation all come from `CenitDesign`. A literal in a screen
is a lint failure, not a matter of taste. The generated index of every component — its role, its
symbol and its file — is [design-system/CATALOGO.md](design-system/CATALOGO.md); read it before
building a component, because the odds are good that it exists.

Adding a token or a component means writing it in `CenitDesign` with a `#Preview`, naming it by role
rather than by appearance, and regenerating the catalog. The token generator is an executable target
in that package, and a workflow re-runs it and fails if the committed output differs.

### The exemption, and its budget

When a rule genuinely must be broken, annotate the line:

```swift
// token-exempt(<categoria>): <reason>
```

The category comes from a fixed taxonomy — a datum, a system constraint, a missing piece, an optical
correction, parity with something else, or a genuine one-off. The reason is prose a reviewer can
judge. Exemptions are themselves ratcheted: their total may go down, not up.

Raising a baseline is legal but narrow. It requires the designated label **and** a diff that touches
nothing but the baseline file and documentation. Both conditions are checked, and the check runs from
the base branch's copy of itself, so a pull request cannot ship a loosened gate.

### Copy

Spanish is the user-facing language and the voice is defined in
[design-system/LENGUAJE.md](design-system/LENGUAJE.md). Three gates enforce the mechanics:

- No Spanish literal in code. The catalog's source language is English, so a Spanish literal becomes
  a Spanish *key* that never translates.
- New keys go under `es`, never `es-MX`. A regional code hijacks the language and leaves plain
  Spanish unresolved.
- No em dash in a Spanish value. Use a colon, a middle dot or a comma.

The key-existence gate carries a self-test that runs first, so a loosened extractor fails loudly
instead of blinding the check.

---

## Adding things

### A metric

1. **Compute it in `CenitAnalytics`**, as a pure function. Cite the published method in the file
   header and write a test with a hand-computed reference value.
2. **Persist it** if it is a per-day scalar: either a nullable column on the day-grain table with a
   new migration, or a row in the long-format metric series if it needs no schema. Prefer the latter
   for anything exploratory.
3. **Read it** through the repository layer, not from a view.
4. **Display it** with existing tokens and an existing chart component.
5. **Say what it is honestly.** If the number is an estimate, the copy says so. A copy gate checks
   that the words next to a number do not overclaim.

### A screen

1. **Check the catalog first.** Most of what a new screen needs already exists as a component.
2. **Design the experience before the pixels** — the flow, and every state: empty, loading, populated,
   error, and permission denied. The permission-denied state is not optional; the app cannot assume
   Apple Health access.
3. **Build it from tokens and components.** A screen file that declares its own colors or spacing will
   fail the linter.
4. **Register what it teaches.** Screens carry a marker naming the features they surface, checked
   against the teaching registry in `CenitEnsenanza`. A new screen file without one fails a gate. **Adding a feature = registering it** (FER-439): the same entry goes into `Tools/ensenanza-semilla.json` (a package test keeps seed and registry equal), its `mapa:` names the Mapa 100 % nodes (`docs/appmap/mapa/<familia>.json`; `Tools/check-ensenanza-mapa.py` cross-checks both ways), and `docs/FEATURES.md` is regenerated from the registry with `python3 Tools/build-features.py` (never edited by hand between its `GENERATED:ensenanza:*` markers; CI runs `--check`).
5. **Cover Dynamic Type and VoiceOver.** The design system has contrast and accessibility tests; a new
   component is expected to pass them.

### A database column or table

1. **Add the next migration.** The current schema is installed by a single migration whose
   identifier is chosen so an existing database reads it as already applied. Do not edit it, and do
   not reuse an earlier identifier: check [DATA_MODEL.md](DATA_MODEL.md) for which one is next.
2. **Use the idempotent column helper** for every addition. A plain alter that re-runs against a
   database which already grew the column throws on every launch and wedges startup, and this has
   happened. Guard a new table the same way.
3. **Choose a default that preserves existing behavior exactly.** The established pattern is that an
   upgrade changes nothing the user can see.
4. **Make null mean absent, not zero.** A nullable column with no default lets the interface
   distinguish "not captured" from a real value; a defaulted zero destroys that distinction forever.
5. **Add a migration test** covering the upgrade path, the fresh-install path, and re-running against
   a database that already has the change.
6. **Update [DATA_MODEL.md](DATA_MODEL.md)** in the same pull request.

---

## Tests

Package tests are the fast loop and where the burden of proof lives:

```bash
cd Packages/<Name> && swift build && swift test
swift test --filter <TestCaseOrMethod>
```

The app's unit tests need a signed simulator build, which `Tools/verify.sh app-tests` handles.

Everything is XCTest except a single design-system file that uses Swift Testing. That matters when
scraping a log: a Swift Testing failure prints `✘ Suite`, not the XCTest format, so a naive grep for
failures can miss it.

A note on fixtures. A test fixture that never crosses the boundary it is supposed to exercise proves
nothing. If a test covers a threshold, the fixture has to sit on both sides of it. If a test covers
Spanish copy, it has to resolve Spanish — a suite running in English silently passes regardless of
what the Spanish says.

---

## Commits and pull requests

Write commit messages that explain the *why*. The diff already shows the what.

- Branch from an up-to-date `iOS`, one branch per issue, named from the issue identifier and a short
  slug. If the branch already exists, someone else owns it.
- Reference the issue so it links and closes on merge.
- Pull requests target `iOS` and are squash-merged; delete the branch afterwards.
- Add a changelog entry for anything user-facing.
- If the change moves the architecture, update [ARCHITECTURE.md](ARCHITECTURE.md) in the same pull
  request. If it settles a question that was open, record it in [DECISIONS.md](DECISIONS.md).
- Label a pull request that touches the app layer so the app workflow runs — but apply the label
  **after** the pull request exists. Passing it at creation has repeatedly caused the labeled run to
  be cancelled, leaving a job that reports skipped without ever running.

Two of the six workflows' jobs are required to merge, both from the design-lint workflow. The rest
are advisory but should be green.

### When a review keeps finding the same defect

If three or more findings share a shape, stop fixing them one at a time. Write the gate, the lint
rule or the test that catches the whole class, run one sweep, and move on. Nearly every gate in
`Tools/` exists because someone did that instead of fixing the fourth instance.
