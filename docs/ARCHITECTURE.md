# Cénit — System Architecture

Cénit is a standalone, fully **offline** health app on **Apple Health**. It syncs HealthKit into
on-device SQLite and computes recovery, strain, HRV, and sleep locally — no cloud, no account. It
can also import Apple Health exports you already own. The app is **Apple-only** (FER-1003): it does
not pair with or read any external wearable.

> Cénit is an independent project. It is **not a medical device**
> and produces **approximate** physiological estimates that must not be used for diagnosis or
> treatment. See [`DISCLAIMER.md`](../DISCLAIMER.md) and [`ATTRIBUTION.md`](../ATTRIBUTION.md).

---

## 1. The big picture

The system is a one-directional pipeline. Health data arrives from Apple Health (live sync) or from
a user-owned import file, lands durably in SQLite, is read back through a thin repository, is turned
into daily metrics by pure analytics functions, and finally renders in SwiftUI. Nothing is ever sent
off-device. The app is **Apple-only** (FER-1003): it no longer pairs with or reads any external wearable.

```
                          ┌─────────────────────────────────────────────────────────┐
                          │                     Cénit (on-device)                     │
   Apple Health           │                                                          │
   ────────────           │   HealthKitBridge                                        │
   HK samples ────────────┼─▶ (CenitApp/Health) ──────────┐                          │
   heartbeat series       │   foreground delta (FER-872)   │                          │
                          │   nocturnal RMSSD (FER-1008)   │                          │
                          │                                ▼                          │
   files                  │                     ┌──────────────────────┐              │
   export.xml / .zip ─────┼─▶ StrandImport ────▶│  CenitStore (actor)  │              │
                          │   (Apple Health     │  GRDB / SQLite       │              │
                          │    parse)           │  decoded streams +   │              │
                          │                     │  metric caches +     │              │
                          │                     │  raw outbox          │              │
                          │                     └─────────┬────────────┘              │
                          │                               │ reads                     │
                          │                               ▼                           │
                          │                      ┌────────────────┐                   │
                          │                      │   Repository   │                   │
                          │                      │ DataSourcePolicy│                   │
                          │                      └───────┬────────┘                   │
                          │                              ▼                            │
                          │               StrandAnalytics ──▶ SwiftUI screens         │
                          │               (HRV/recovery/      (CenitDesign)          │
                          │                strain/sleep)                              │
                          └─────────────────────────────────────────────────────────┘
```

The same `CenitStore` SQLite file is the single convergence point for HealthKit sync and file
imports. All readers go through `Repository`. Old legacy device partitions (raw + computed)
remain **dormant** in SQLite — excluded at read time by `DataSourcePolicy` under the pinned
`.appleHealthOnly` mode (`SourceModeStore`), **never deleted** (so a backup/restore keeps history
and dormant legacy rows cannot win over Apple in the merge).

---

## 2. Repository layout

```
Cenit/                         App-layer (Data/Screens/System/…) compiled by the iOS target
├── App/                        App state (the iOS app scene lives in CenitApp/)
│   ├── AppModel.swift          @MainActor root state — owns Repository, profiles, strength session, Watch mirror
│   └── ContentView.swift
├── Data/                       Read model + import glue + on-disk paths
│   ├── Repository.swift        @MainActor read model over CenitStore
│   ├── StorePaths.swift        on-disk SQLite location (App Support/Cenit/cenit.sqlite — see §2)
│   ├── SourceModeStore.swift   data-source mode (pinned `.appleHealthOnly`, FER-1003)
│   ├── AppleHealthImport.swift Apple Health / file-import result → store rows
│   ├── Profile.swift           user profile (age/sex/body/HRmax)
│   └── BehaviorStore.swift     toggles for automations/coaching
├── Screens/                    SwiftUI feature screens (Today, Sleep, Trends, Train…)
├── Media/                      opt-in exercise-media cache/download (off by default)
├── LiveActivity/               Live Activity / rest-timer presentation glue
├── Onboarding/                 first-run / restore / terms flows
└── System/                     app-layer helpers (ProjectInfo, Platform)

Packages/                       Cross-platform Swift packages (base `.iOS(.v16)` / `.macOS(.v13)`;
│                               CenitDesign is `.iOS(.v17)` / `.macOS(.v14)` + `.watchOS(.v10)`)
├── BiometricStreams/           neutral vocabulary of decoded rows (`Streams`, `ParsedValue`) — no deps; still linked into the app (CenitStore/StrandAnalytics depend on it)
├── CenitStore/                 GRDB/SQLite persistence (actor)
├── StrandTraining/             strength domain types + bundled exercise catalog (free-exercise-db, FER-923; pure, no DB)
├── CenitEnsenanza/             registro tipado de funcionalidades (qué se enseña, dónde, con qué pieza); pure, no deps (FER-430)
├── StrandAnalytics/            HRV/recovery/strain/sleep/correlation math
├── StrandImport/               Apple Health importer (export.xml, streaming) + StrengthCSVImporter (Strong/Hevy/Cénit CSV)
└── CenitDesign/               SwiftUI design system (palette, components, charts)

CenitApp/                       iOS SwiftUI app shell (App/Health/System/Widgets/Resources)
CenitShared/                    code shared between the iOS app, its widgets, and (FER-740) the watch —
                                incl. the workout-mirroring contract (WorkoutMirrorMessage, RestActivitySnapshot)
CenitWidgets/                   iOS home / lock-screen widgets
CenitWatch/                     watchOS 10 companion app (single target, FER-740). Runs the real
                                HKWorkoutSession and mirrors it to the iPhone; no GRDB on the wrist.
                                Depends only on CenitDesign (project.yml + `import CenitDesign` only).
```

The app target is **`Cenit`** (Swift module `Cenit`, product `Cenit.app`): its shell (scene, HealthKit,
widgets, intents) lives in **`CenitApp/`**, and it compiles the app-layer under **`Cenit/`** (screens,
data, media). Its linked packages (`project.yml`) are `BiometricStreams`, `CenitStore`,
`StrandAnalytics`, `StrandImport`, `CenitDesign`, `StrandTraining` and `CenitEnsenanza` (FER-398 dropped `Inject`: the
hot-reload shim now lives in-repo at `Cenit/System/HotReload.swift`, so no dev-only third-party code
ships in the store binary). The user-visible name
stays **Cénit** (`CFBundleDisplayName`); the visible rebrand to "Cénit" is tracked separately. The macOS
app and its `Strand`/`StrandTests` targets were retired (FER-143) and the dead `#if os(macOS)`/`AppKit`
branches removed (FER-144); the app-layer unit tests run as **`CenitUnitTests`** in the simulator. The
packages keep their `Strand*` names. The core/data/analytics packages declare `.iOS(.v16)`/`.macOS(.v13)`,
guarding UI-framework calls behind `#if canImport(UIKit)` / `#if canImport(AppKit)`. **`StrandTraining`**
keeps that base (`.iOS(.v16)`/`.macOS(.v13)`) and also declares **`.watchOS(.v10)`** (FER-740).
**`CenitDesign` is higher:** `.iOS(.v17)` / `.macOS(.v14)` / `.watchOS(.v10)` so the watch app can paint
with the design tokens — both are pure (Foundation-only / SwiftUI behind `#if canImport(UIKit|AppKit)`,
with `#if os(iOS)` guards on the two haptic/hover-scrub spots). `CenitStore`/`StrandAnalytics`/
`StrandImport` are **not** watchOS-bound: no DB or analytics runs on the wrist.

**Legacy identifiers migrated once at launch (FER-398).** The on-disk container and the
`UserDefaults` keys used to be frozen under the NOOP names, because renaming either one silently
resets a live install. They are unfrozen now, each behind its own one-time migration, run from
`CenitApp.init()` **before `AppModel()` opens the store**:

- **Container** — `<AppSupport>/OpenWhoop/whoop.sqlite` → `<AppSupport>/Cenit/cenit.sqlite`.
  `StorePaths.migrateLegacyContainerIfNeeded(appSupport:)` does ONE atomic folder rename, which
  carries the DB, its `-wal`/`-shm`, any restore sidecar and `MediaCache/` together — no window
  where half the data is in each place. The file rename that follows is **sidecar-first, main file
  last**, so the main file's name is the "done" mark and an interrupted run resumes on the next
  launch. When `Cenit/` already exists but holds no database of either name — an interrupted first
  run, or a folder a path helper created — the rename has nowhere to land, so the legacy container's
  **contents** are merged into it entry by entry (same order, main file last, never overwriting a
  destination that exists) rather than the app opening empty on top of a full `OpenWhoop/`. Nothing
  is ever deleted: if the move fails, the old folder stays whole and the app opens on an empty
  `Cenit/`. It returns a `LegacyMigrationOutcome`, and `StorePathsMigrationTests` covers the move, a
  fresh install, both-containers-exist, the merge into an existing folder, the resumed crash and
  idempotency.
- **Preferences** — `noop.*` → `cenit.*`. `PrefKey` is the single enum of every key Cénit persists
  (with its suite: `.standard` or the App Group), and `PrefMigration.migrateLegacyKeysIfNeeded`
  **copies then deletes**, key by key, over `allCases` — so a key added to the enum can never be
  forgotten by the migration. Idempotent with no flag of its own: after the first run there is no
  legacy key left to find. **One deliberate exception:** `exerciseMediaEnabled` /
  `exerciseMediaMissedIds` are NOT in the enum and are *deleted* rather than migrated — the exercise
  media card left Settings in the same change, so carrying a `true` forward would leave an install
  networking with no control to stop it (see the Exercise media bullet in §9).
- **Not migrated here:** the persisted schema tags `noop.workout.v1` / `noop.diet.v1` are wire
  contracts of `StrandImport` and move with that package, not with this file.

The bundle id and App Group used to be frozen alongside them, but were **not** in the end: the old
App ID turned out to be registered to a different Apple team, so Xcode refused to provision any of
the three signed targets ("cannot be registered to your development team because it is not
available"). The prefix moved to `com.feriracheta.cenit` — bundle ids, App Group, the exported drag
UTType and the Darwin notification all in step. **Cost of that move:** the App Group is a new
container, so any data already in the old one (the Live Activity rest-action inbox, Shortcuts'
`PendingIntents`) does not carry over — both are transient queues, so nothing durable was lost, but
a device installed with the old id keeps the old app side by side until it's deleted.

The App Group in particular is declared **once**, in `AppGroup.suiteName` (`CenitShared/`, compiled into
the app, the watch and the widget extension); every consumer reads it from there rather than repeating the
literal. This matters because the failure is silent: `UserDefaults(suiteName:)` returns a *non-nil* store
for a suite the target isn't entitled to — backed by a private plist, so even a write/read round-trip
succeeds — so a second copy of the string can drift for a long time without anything breaking loudly.
(It did: the constant still named the project's predecessor while every entitlement used the current
identifier.) The only reliable probe is `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`,
which returns nil on iOS when the entitlement is missing; `AppGroup.warnIfGroupUnprovisioned()` uses it
at launch.

---

## 3. Package responsibilities and boundaries

Each package has a narrow contract. The dependency graph is acyclic and the leaf packages are
**platform-pure** (no CoreBluetooth, no UIKit/AppKit) so they run in CLI tools and tests:

```
CenitDesign        (no deps — pure SwiftUI)
StrandTraining      (no deps — pure domain types + bundled exercise catalog)
StrandModels        (no deps — shared daily-metric value types: DailyMetric, CachedSleepSession, DietMealStatus)
CenitEnsenanza      (no deps — the typed teaching registry: 68 features × {pestaña, requiere, piezas}; linked to the app only)

BiometricStreams    (no deps — the ROOT: the neutral vocabulary of decoded biometric rows)

CenitStore ─────────▶ BiometricStreams + StrandModels + StrandTraining + GRDB.swift
StrandAnalytics ────▶ BiometricStreams + StrandModels  (NO CenitStore/GRDB: pure math over value types —
                                                       L3-C1b. NO StrandTraining dep: the strength engines —
                                                       MuscleFatigueMap FER-350, the 1RM estimator FER-346,
                                                       WeeklySplit FER-531 — take plain primitives the app
                                                       projects from StrandTraining types, keeping
                                                       StrandAnalytics decoupled)
StrandImport ───────▶ CenitStore + StrandTraining + ZIPFoundation
```

> **`BiometricStreams` is the root of the graph (FER-993 · D2).** It owns the *vocabulary of decoded
> data* — `HRSample`, `RRInterval`, `StreamEvent`, `BatterySample`, the type-47 biometric samples,
> `Streams`, and `ParsedValue`. It is Foundation-only and depends on nothing, so persistence
> (`CenitStore`) and math (`StrandAnalytics`) speak it directly. It stays source-agnostic: nothing here
> names a frame, a byte, or a specific device, and there is **no `@_exported import`** — the boundary has to be
> verifiable by the compiler, which a re-export would erase.

| Package | Responsibility | Key types / functions | Notable boundary |
|---|---|---|---|
| **StrandModels** | Shared daily-metric value types used by both persistence and analytics — the durable shapes of cached scores, sleep sessions, and diet adherence status. | `DailyMetric` (+ `FieldUpdate`/`with(...)`), `CachedSleepSession`, `DietMealStatus` | **Leaf — zero dependencies, Foundation only.** No GRDB/UIKit. `CenitStore` depends on it and re-exports the names via `public typealias` (L3-C1a); `StrandAnalytics` depends on it directly (L3-C1b) so math never links GRDB. |
| **BiometricStreams** | The neutral vocabulary of decoded biometric rows — the durable shapes everything downstream stores, computes over and serializes. Source-agnostic: nothing here names a frame, a byte, or a specific device. | `HRSample`, `RRInterval`, `StreamEvent`, `BatterySample`, `SpO2Sample`, `SkinTempSample`, `RespSample`, `GravitySample`, `StepSample`, `Streams` (+ `.empty`), `ParsedValue` | **Root of the graph — zero dependencies, Foundation only.** No CoreBluetooth/UIKit/AppKit/GRDB, and no CRC/UUID/CLIENT_HELLO/schema. (FER-993 · D2). **Still linked into the app binary** — `CenitStore` and `StrandAnalytics` depend on it (`project.yml` lists `BiometricStreams` under the `Cenit` target). |
| **CenitStore** | Durable on-device persistence built on GRDB/SQLite. Migrations, decoded streams, metric caches, generic metric series, raw outbox, cursors. | `actor CenitStore`, `makeMigrator()`, `insert(_:deviceId:)`, `dailyMetrics`, `sleepSessions`, `metricSeries`, `pruneRaw`, `ClockRef`, `RawBatchMeta` | An **`actor`** — all writes/reads run off the main thread on its serial executor. |
| **StrandAnalytics** | All physiological math, as pure functions over inputs. HRV, strain, energy, baselines, HR zones, correlation/comparison. | `HRVAnalyzer`, `StrainScorer`, `Calories`, `Baselines`, `HRZones`, `ReadinessEngine`, `CorrelationEngine`, `Preparedness` (the «Preparación» morning verdict by axis-consensus over the user's Apple baselines — composed in `Repository.performRefresh`, published as `DashboardData.preparedness`, read by the Today hero; FER-1030), `WeeklySplit` (split → today's routine / day states / consistency streak, FER-531) | **Pure — never touches the database (literal):** depends on `BiometricStreams` + `StrandModels` only; no GRDB/CenitStore link (L3-C1b). Produces `DailyMetric`/`CachedSleepSession` shapes for the store. |
| **StrandImport** | Parse Apple Health exports the user already owns (`export.xml`, streaming). | `ImportCoordinator.detectAndImport`, `AppleHealthImporter`, `AppleHealthAggregator`, `SleepHKEncoder`/`SleepHKDecoder` | **Parsing only** — returns normalized model arrays; the app maps them into the store. |
| **CenitDesign** | The SwiftUI design system: palette, typography, motion, charts, components. | `StrandPalette`, `liquidGlass(_:)`, `RecoveryZoneGauge`, `Hypnogram`, `TrendChart`, `Sparkline`, `YearHeatStrip` (full index: [CATALOGO.md](design-system/CATALOGO.md)) | No data or protocol deps — pure presentation. |
| **StrandTraining** | Strength-tracker domain types + the bundled, read-only exercise catalog (**free-exercise-db**, 873 exercises with native slug ids; FER-923, was ExerciseDB OSS in FER-779). The value models CenitStore persists and StrandAnalytics computes over. | `Exercise`, `ExerciseType`, `ExerciseCatalog`, `Routine`, `RoutineExercise` (with `supersetGroup` FER-346; optional fixed note seeded into each session and never copied to the session's acta, FER-166, v39), `RoutineSet` (per-set prescription, FER-492; optional per-set `RestConfig` override with exercise fallback, FER-715; optional `repsRangeTop` for a "floor-top" rep range, FER-94, migration v38), `RoutineSchedule` (the weekly split, FER-531), `StrengthSession` (with persisted `energyKcal`/`EnergySource`, FER-715), `SetEntry` (with `rpe` v34; `restTakenS` — the real rest that FOLLOWED the set, pause-excluded, captured by the live session, FER-167, v40), `PersonalRecord`; **the program engines** (ola 1 · FER-329): `Program` + `ProgramCalendar` (the ONE oracle of «which week am I in?» — derived from `startTs` + the weeks actually trained, never stored), `ProgramDeload` (the light-week rule; returns RAW kg, like `SetVariants`, because the plate rounding lives in `PlateMath`) and `ProgramTemplate` (the four engines, as data over `StarterTemplates`); `StarterGroupSchedule` + `WeeklySchedulePlanner` (FER-377 — the per-`StarterTemplate.Group` weekly frequency/spacing recipe and the pure, `taken`-aware placement of a group's routines across the week, best-effort; the app-layer `applyTemplateGroup` composes them) | **Pure** — Foundation only (no GRDB/UIKit). GRDB conformance lives in CenitStore by extension. (FER-345) |
| **CenitEnsenanza** | The single declaration of how each feature is taught: `FuncionalidadID` (stable id = TipKit id), `Pestana`, `Requisito`, `Pieza` (`.vacio/.tip/.hito/.ayuda/.novedad/.gestoConBoton`), `Registro` (per-tab seed). Text and routes only — never logic or state (one documented exception: `EstrofasSync`, the pure, tested rule of the onboarding sync strophes, FER-437). | `Registro.todas`, `Registro.por(_:)`, `Funcionalidad.nombreKey/paraQueKey/dondeViveKey` | **Leaf — Foundation only**, runs on Linux CI. Copy lives in the app catalog (keys `ensenanza.<id>.*`); `CenitDesign` never imports it (`LiquidVacio` takes `Text`). |

> **Exercise type override (FER-541).** The user can override an exercise's `ExerciseType` — including a catalog entry's (e.g. mark a "Plank" as time-based). The override is *user data*, so it lives in CenitStore (`exerciseTypeOverride`, migration v24), **not** in the read-only bundled catalog. Precedence (user override > custom > catalog) is decided by the pure `ExerciseTypeResolver` and applied at a single resolver in `Cenit/Data/Repository+Strength.swift` (`resolvedExercise` / `allExercises`), which materializes the effective type into `Exercise.type`. Every downstream reader (guided session, builder, detail) sees the resolved type without bespoke logic; the catalog JSON is never mutated, so reverting is a plain delete.

> **Catalog adoption (FER-779 → FER-923).** The seed catalog is **free-exercise-db** (yuhonas — 873 real exercises, **The Unlicense / public domain**, native slug ids like `Barbell_Bench_Press_-_Medium_Grip`), baked offline by `Tools/bake-exercisedb/` into `exercises.json(.zlib)` (+ an `exercises.es.json(.zlib)` es-MX overlay, LLM-translated at bake). It **replaced ExerciseDB OSS** (~1500, non-commercial license + duplicates/junk) in FER-923: since Cénit ships its **own art** (FER-919), the base only needs clean data + a sane license, not media. free-exercise-db already uses Cénit's 17 canonical `MuscleAtlas` keys (identity, zero remap; `MuscleAtlas`/`MuscleVocabulary`/`MuscleFatigueMap` untouched); the bake derives `ExerciseType` from category/equipment/name and `bodyParts` from `primaryMuscles`. `Exercise.id` is the native slug, so media/data resolve **by id, without name matching**. The model carries `instructions`/`bodyParts`/`gifUrl`; custom exercises persist those via migration **v27**.
>
> **History remap (FER-923, migration v33).** Because the catalog source changed, the exercise ids changed too — and the user's saved history *does* reference them (`routineExercise`, `setEntry`, `personalRecord` [composite id `exerciseId:metric`], `learnedExerciseAlias`, `exerciseTypeOverride`, `progressionOptOut`). So FER-923 adds a **real history migration** (superseding FER-779's "no migration, fresh start" stance): v33 loads two baked maps from CenitStore's bundle — `exercise-id-remap` (old ExerciseDB id → new slug, exact-name match) and `legacy-exercise-data` (old id → its record, for ids with no match) — and for every in-use id either **rewrites** the reference to the new slug, **materializes** a `customExercise` carrying the old id (no match), or leaves it (already a slug / user custom). Invariant: **zero orphaned history** (`MigrationTests.testV33Remap`). The bake also drops the old ExerciseDB stills (the new catalog ships no media; Cénit art lands per-id in FER-919) and rebuilds the import alias table (`build_aliases.py`) against the new names.

---

## 4. The actor / concurrency model

Concurrency is deliberately split between the store actor and the main-actor app surface:

| Component | Isolation | Why |
|---|---|---|
| `CenitStore` | **`actor`** | GRDB calls block; the actor moves that blocking off the main thread and keeps **writes** serialized (a single writer per handle). `Repository` opens the handle as a **`DatabasePool` (max 2 readers)** (FER-970 · R-04) so the nonisolated bulk read (`dashboardSnapshot`) runs on WAL reader connections and never queues behind a long engine/import write. |
| `AppModel`, `Repository`, `HealthKitBridge`, other bridges | **`@MainActor`** | These observe/mutate published UI state and orchestrate reads/writes through the single store handle. |

There is **one** `CenitStore` handle in the shipping app: `Repository.ensureStore()` creates
`CenitStore(path:backend: .pool(maxReaders: 2))` and exposes it as `storeHandle()`. HealthKit sync
(`HealthKitBridge`) and the import glue (`AppleHealthImport` and related file-import mappers) all
write through that handle via `repo.storeHandle()` — no second BLE-side `DatabaseQueue` remains
(app-layer BLE was deleted in FER-1003).

`CenitStore` still enables **WAL journal mode** and a **5-second busy timeout**
(`PRAGMA journal_mode = WAL`, `config.busyMode = .timeout(5)`), so concurrent readers on the pool and
the actor-serialized writer never deadlock on contention. Write-mode PRAGMAs are guarded to writer
connections (`!db.configuration.readonly`), and `wal_checkpoint(TRUNCATE)` / `VACUUM` use barrier
writes. The pool exists so the nonisolated dashboard snapshot does not wait behind a long write on
the same handle (IntelligenceEngine upserts, imports, HealthKit pulls).

---

## 5. Apple Health ingestion / imports

Primary ingestion is Apple Health plus optional file imports — not a BLE wearable pipeline.

**Foreground HealthKit sync (FER-872).** `CenitApp` calls `await health.sync(trigger: .foreground)`
when the scene becomes active (`CenitApp.swift`). `HealthKitBridge.sync` pulls HealthKit samples into
`CenitStore` through `repo.storeHandle()`. The first foreground sync of a process session uses the full
window; subsequent foreground syncs use a **delta window** from `lastSync` plus a few days of
back-margin (`deltaBackMarginDays`), and skip a redundant dashboard rebuild when the pulled Apple rows
fingerprint unchanged. Manual / onboarding / re-bucket callers keep `.manual` (full window).

**Nocturnal beat-to-beat RMSSD (FER-1008).** During sync, `HealthKitBridge.ingestNocturnalHRV` reads
Apple heartbeat series for recent nights, runs pure `NocturnalHRV` (`StrandAnalytics`), and writes
`apple_rmssd_night` / density counts under a dedicated Apple-computed partition (`metricSeries`).
`Repository.autonomicTrend` reads those points for the categorical `AutonomicTrend` on Today. See §7
"Generic metric series" for the partition invariants.

**File imports.** `StrandImport` remains parse-only; the app's `AppleHealthImport` writes results into
the same store (see §8). Under the pinned `.appleHealthOnly` mode, `DataSourcePolicy` filters reads so
dormant legacy device partitions (raw + computed) never enter the dashboard merge.

**Historical note.** The former live BLE path, historical offload/safe-trim, and connection lifecycle
were removed in the band amputation (FER-1003).

### Watch-mirrored strength sessions (FER-740, F1.1 of the Apple Watch epic FER-391)

A guided strength session can run as an **`HKWorkoutSession` mirrored from the Apple Watch** (iOS 17 /
watchOS 10 workout mirroring). The wrist (`CenitWatch/`) runs the real `HKWorkoutSession` and mirrors it
to the iPhone; there is **no GRDB on the watch**. State crosses the pairing over two channels: HealthKit's
mirror payload (`sendToRemoteWorkoutSession`, best-effort — rest windows via the reused
`RestActivitySnapshot`, pulse) and `WatchConnectivity` (`WCSession`, guaranteed + acked — the control
messages: start / end / "watch saved" / "watch won't save"). The single contract is `WorkoutMirrorMessage`
in `CenitShared`; the iPhone half is `WorkoutMirroringBridge` (`CenitApp/Health/`), wired into `AppModel`.

The iPhone stays the **single source of truth**: it persists the session to `CenitStore` before any
HealthKit/watch step (decoded-first, unchanged). The **one-`HKWorkout` invariant** is held by the
deterministic shared key `HKMetadataKeyExternalUUID` (a fixed prefix + `<sessionId>`): whichever device writes,
the write is idempotent (delete-by-key then save). The iPhone omits its own `saveStrengthWorkoutIfEnabled`
**only** on a positive `watchDidSaveWorkout` ack (`WorkoutSaveGate`); otherwise it saves, so a missing/absent
watch is regression-free. Live heart rate on the strength sheet comes from the **Apple Watch mirror**
(`AppModel.watchBpm`, FER-1003) — the watch is both control surface and live-HR source for in-session
UI. That pulse is **not** merely a transient UI read: `AppModel.ingestWatchPulse` (FER-226 — revives
what F7's band amputation had accidentally killed) ALSO admits it into the session's HR buffer and
persists it to `CenitStore.strengthHrSample` (§7), so `avgHr`/`strain`/`energySource` on the finished
session's receipt, and a mid-session crash's recovered average, are backed by real durable samples, not
memory that dies with the process. Folding more Watch physiology into the recovery/strain engine
remains open product work.

The in-progress session is **durable across a crash/kill of the iPhone** (FER-798): a Codable
`StrengthSessionSnapshot` (defined in `StrandTraining`) is written to `CenitStore`'s singleton
`inProgressStrengthSession` table on start and on each durable edit (debounced; immediate on rest
start/end), and restored in the launch `analysisTask` — so the Apple Watch's queued `.end` finds a live
session and saves the receipt instead of dropping the workout. The snapshot is deleted on save/discard.
The `HKWorkout` mirror is **not** rebuilt from the snapshot — HealthKit re-delivers the `mirroredSession`
when the process relaunches; the one-`HKWorkout` invariant is resolved at end time (`WorkoutSaveGate` +
the deterministic `externalUUID`), never from persisted state. When no session is recoverable, a hook
(`onNoRecoverableStrengthSession`) lets a caller close any orphaned Live Activity (FER-806).

### Session Live Activity + the app→widget media channel (FER-721 / FER-789 / FER-806)

FER-806 generalizes this from a **rest-only** Activity to one that lives the **whole session**: it is born
when the strength session starts (the `strengthSession` `didSet` → reconcile already produces a snapshot)
and persists through the active set, rest and pause until the receipt is up, then ends. `computeRestSnapshot`
became `computeSessionSnapshot`, gated on a pure `AppModel.sessionPhase(for:)` (`paused` → `.paused`;
`resting` → `.resting`; else `.active`) that returns `nil` (no session / receipt up) so the Activity ends.
The contract grew four Optional/defaulted fields (`sessionPhase`, `sessionStartedAt` = the effective active
anchor excluding paused time, `setsDone`/`setsTotal`); a pre-FER-806 Activity decodes them `nil` and the view
falls back to the rest layout. The lock-screen actions gained `resume` (leave «En pausa»), and `completeSet`
now applies in the active phase too (the «Completar» button). Crucially, the launch-time `endOrphans()` is no
longer unconditional — it would kill a legitimate card before crash-recovery restores its session; instead
FER-798's `onNoRecoverableStrengthSession` hook ends the orphan **only** when no session is recoverable (a
recoverable one is restored first and its reconcile adopts the running Activity). `staleDate` is
`restEndsAt + margin` in a rest but a rolling 1 h window in the active/paused phases (renewed per update; on
app death it expires → the card paints its `context.isStale` «Abre Cénit para continuar» state). The Apple
Watch mirror keeps FER-721's **rest-only** semantics (it only receives `pushRest` while genuinely resting),
so the wrist never shows a phantom countdown mid-set.

The same `RestActivitySnapshot` (`CenitShared`) drives the **session Live Activity** on the lock screen /
Dynamic Island (`RestActivityController`, `Cenit/LiveActivity/`) → `RestActivityAttributes.ContentState`
(`CenitWidgets/Shared/`, ActivityKit-gated). Lock-screen buttons fire `LiveActivityIntent`s
(`RestActivityIntents`) that don't apply anything inline — they **enqueue** onto a durable inbox in the
shared App Group `group.com.feriracheta.cenit` (`RestActivityBridge`: `UserDefaults(suiteName:)` + a Darwin
notification), and the app drains it into `AppModel.applyRestAction` → the live `StrengthSessionModel`; the
normal reconcile loop reflects the result back onto the Activity. FER-789's four actions map to existing
model methods — **Completar ≠ Saltar**: `completeSet` logs the upcoming set (`registerCurrentSet`) and rests
again, `skip` only cuts the timer; `±30` is `extendRest` (−30 floored at now); `finishWorkout` registers the
last set and ends the session. The `ContentState`/`RestActivitySnapshot` contract is **additive and
Optional** so an Activity started under an older app decodes unchanged (missing keys → nil).

The widget extension can't read the app-local `MediaCache` (`applicationSupportDirectory`), so FER-789 opens
a **one-way app→widget media channel** through the App Group: `RestThumbnailProvider` (app) copies the active
exercise's already-cached thumbnail into `group…/RestThumb/<name>.jpg` at each rest, and the widget resolves
it via the shared `RestThumbnailStore` (same path constant, compiled into both targets). The snapshot carries
the file **name only, never image bytes** (kept small — ActivityKit serializes it on every update); the file
is a single slot, overwritten per rest and cleared when the rest/session ends and at launch. The
**"no thumbnail" state is first-class** (exercise media is opt-in, §"Network exceptions") — the card omits the
circle, never a placeholder. No network is introduced; the provider only copies a file the opt-in media
download already fetched.

---

## 7. Storage model (CenitStore / SQLite)

GRDB drives a migrator with **exactly one** registered migration, `"v43"`, whose body is the whole
DDL (`Schema.swift` — the source of truth is that list, never a hand-written constant).

The identifier is load-bearing (FER-393). A database installed before the clean-room rewrite carries
the 43 identifiers `v1`…`v43` of the previous incremental history in its `grdb_migrations` ledger, and
GRDB silently ignores applied identifiers a migrator doesn't know about — so that database reads
`"v43"` as applied, finds nothing pending, and **executes not one schema statement**. A fresh install
arrives with an empty ledger, runs `"v43"`, and gets the full schema. Two consequences, both pinned by
tests: **the next migration is `"v44"`** (reusing `"v1"`…`"v42"` would be skipped in silence on an
installed database, leaving its schema behind with no error), and **`eraseDatabaseOnSchemaChange`
stays off** (with it on, GRDB would read those 43 unknown identifiers as a schema change and erase the
file). The DDL is pasted verbatim from a `.schema` dump of a real migrated database
(`Tests/CenitStoreTests/Resources/legacy-schema.sql`) and a test compares `sqlite_master` against it
character by character; the guard against a second execution lives in Swift, checking `sqlite_master`
per object, so the recorded text stays exact.

The schema groups into five concerns:

**Durable beat streams** — `hrSample` (`(deviceId, ts)`) and `rrInterval` (`(deviceId, ts, rrMs)`),
one row per sample. The band-era stream tables (`event`, `battery`, `spo2Sample`, `skinTempSample`,
`respSample`, `gravitySample`, `stepSample`, `rawBatch`, `device`, `circadianPhase`) were dropped and
are not recreated; `Streams` still carries the dormant arrays, and `insert` simply does not persist
them — writing to a table that isn't there would throw and take the beats down with it.
- Both are **`WITHOUT ROWID` + `STRICT`** with an **integer `deviceId` surrogate**. A rowid table with
  a composite PK keeps a second `sqlite_autoindex` copy of the key + rowid on every row (~46% of the
  DB); `WITHOUT ROWID` makes the natural PK *be* the table, and the surrogate replaces a repeated TEXT
  label on every one of ~86 000 rows per day of pulse. Neither carries the dead `synced` column of the
  retired upload feature.
- The surrogate map is **`deviceIdMap(deviceId TEXT PK, intId INTEGER UNIQUE)`**. `CenitStore`
  translates at the actor boundary through a `[String: Int64]` cache it owns (the actor serializes
  lookup-then-insert, so two callers can't assign two integers to one label), and the public read/write
  API still takes `deviceId: String`. A read of an unknown partition returns empty instead of throwing;
  a write creates the mapping on demand, so an insert can never fail for a missing surrogate.

**Metric caches** — the rolled-up shapes the screens read. The name is a little misleading: there is
no invalidation, no dirty flag and no notification anywhere in the package. They are durable rows of
already-computed values, rewritten by whoever recomputes them.
- `dailyMetric` — one row per `(deviceId, day)`: `recovery`, `strain`, sleep stage minutes,
  `restingHr`, `avgHrv`, `spo2Pct`, `skinTempDevC`, `respRateBpm`, `exerciseCount`, `steps`,
  `activeKcalEst`, and the two confidence tiers. Its conflict rule is **not** a replacement: the
  engine re-scores every night in its window on each pass, and a night whose sleep session isn't
  detected yet comes back all nulls, so each column merges as `COALESCE(incoming, stored)` and a day
  is cleared by DELETING it, never by writing nulls over it. `strain` merges by a narrower rule a
  plain `COALESCE` gets wrong in one case — a stored `0` (usually a false rest from a pass without
  pulse) may go back to NULL, while a stored load above 0 never degrades to rest or to «no data». The
  seven cases are pinned one by one in `DayCacheStoreTests`.
- `sleepSession` — one row per `(deviceId, startTs)` with `efficiency`, `restingHr`, `avgHrv`, and
  a JSON `stagesJSON` hypnogram. Reads return the sessions that **overlap** the window, not the ones
  that start inside it: falling asleep before local midnight puts the night's start outside the
  window, and it is still that night.
- `journal`, `workout`, `appleDaily` — journal answers, workouts (imported history + Apple Health),
  and Apple-Health daily aggregates. All three arrive in batches, and SQLite refuses to resolve the
  same conflict key twice inside one `INSERT … ON CONFLICT DO UPDATE`, so a batch is deduplicated
  first, keeping the LAST appearance of each natural key in first-appearance order — «row by row, last
  wins», resolved before the write. `dailyMetric` can't use that shortcut (its rule merges column by
  column, so collapsing would lose what only the first appearance carried) and is split into passes
  instead, which applied in order reproduce row-by-row semantics exactly.
- `experiment` (v12, FER-307) — one row per N-of-1 experiment, natural key `id` (UUID): the lever
  (`behavior` × `outcome`), `startDay`/`windowDays`, `status` (running/completed/canceled), and the
  verdict columns filled on completion. Additive only; one experiment runs at a time (app-enforced),
  but the table keeps the full history.
- `dietPlan` / `dietAdherence` (v14, +v16, FER-370/401) — a prescribed diet plan stored as an opaque
  JSON `payloadJSON` (PK `id`, + denormalized `nombre`/`idioma`/`ciclo`/`createdAt`),
  and per-meal daily adherence keyed `(deviceId, day, mealId)` with a tri-state `status`
  (cumpli/sustitui/salte) plus a nullable `optionIndex` (v16, FER-401) recording WHICH equivalent
  `opciones` index was eaten — registro only, it does not change the apego %. CenitStore never decodes
  the plan (that's `StrandImport.DietPlan`); the apego % (FER-372) is computed from `dietAdherence`
  against the active plan's meal count. Mirrors `journal`.
- `inProgressStrengthSession` (v28, FER-798) — a singleton control table (0 or 1 row, PK `id`) holding a
  Codable `StrengthSessionSnapshot` as an opaque JSON blob: the guided strength session in progress, so a
  crash/kill of the iPhone doesn't lose the workout (written on start + each durable edit, restored at
  launch, deleted on save/discard). Ephemeral control state — prunable, outside the `WITHOUT ROWID`
  rebuild and the sync bookkeeping.
- `progressionOptOut` (v31, FER-835) — one row per `(sessionId, exerciseId)` when the user tapped
  «Volver a X» in that session: the load-progression classifier treats the session as neither hit nor
  miss. Written atomically inside `saveSession` (delete-first, so a re-save is idempotent), cleaned by
  `deleteSession`, surfaced by `workSetHistory` via LEFT JOIN, consumed as
  `ProgressionMath.PastSession.optedOut`.
- `workSetHistory` (FER-147) returns `WorkSetHistoryRow` (`sessionId`, `startTs`, `weightKg`, `reps`,
  `optedOut`, `rpe`, `routineName`) — one JOIN of `setEntry` × `strengthSession`, LEFT JOIN
  `progressionOptOut` and LEFT JOIN `routine` (so a since-deleted routine reads `routineName == nil`,
  not a crash). `rpe` (v34) feeds the Historial tab's «QUEDABAN» read (10 − RPE); `sessionId` is the
  per-row grouping key. The row cap keeps the MOST RECENT sets (`ORDER BY startTs DESC LIMIT ?`,
  re-sorted ASC), not the oldest.
- `setEntry.restTakenS` (v40, FER-167) — the real rest that FOLLOWED each logged set, in seconds,
  pause-excluded: captured by `StrengthSessionModel` (the rest phase's actual run for its owner set —
  closed by skip/auto-skip, the next check-off, or an inline done; navigation jumps and session end
  DISCARD an open rest), persisted through `saveSession`, read back by
  `realRestSeconds(routineId:sessionLimit:)` and averaged by the pure `StrandTraining.RestStats`
  (interruption cap 900 s) for the hub's «DESCANSO REAL» tile. NULL = no measured rest (last set,
  intra-round superset jump, «sin descanso», pre-v40 rows) — never a default 0.
- `strengthHrSample` (v41, FER-226) — one row per `(sessionId, ts)`: raw watch-pulse samples captured
  during a live guided strength session, reviving the capturer F7 ("la banda nunca existió") had
  accidentally amputated with the band. `AppModel.ingestWatchPulse` admits each pulse through the pure
  `StrandTraining.StrengthHRIntake` gate (drops it while paused, outside 25…240 bpm, or repeating the
  last accepted timestamp) and flushes to `CenitStore.appendStrengthHR` every 30 samples plus once more
  at save (`attemptStrengthSave`) — the natural `(sessionId, ts)` PK makes a retried flush a no-op for
  whatever already landed, never a duplicate. `AppModel.restoreInProgressStrengthSessionIfNeeded`
  rehydrates `StrengthSessionModel.hrSamples` from this table (which the JSON snapshot omits, being
  memory-only) so a crash mid-session doesn't lose the average. Cleared by `deleteStrengthHR` on a
  discarded session and cascade-deleted by `deleteSession`. No FK — the session row is never gone out
  from under a live capture, and app-level ownership is enough for a table this narrow.

**Generic metric series** — `metricSeries(deviceId, day, key, value REAL)`: a tall, long-format
table so *any* scalar metric from *any* source can be queried/compared uniformly (the substrate for
the Metric Explorer and correlations), indexed by `(deviceId, key, day)`. The nightly frequency-domain
HRV powers (`hrv_lf` / `hrv_hf` / `hrv_totalpower`, ms², FER-702) persist here under a legacy
computed-source suffix — an additive scalar cache with no schema change, alongside `steps_est` and the stress
aggregates. FER-868 added the daily motion derivatives under the same computed-source suffix: `motion_intensity`
(the civil day's gravity motion volume, `StepsEstimateEngine.dayMotionIntensity` — the steps-estimate
input) and `act_h00`…`act_h23` (the per-local-hour motion profile feeding `CircadianEngine`'s cosinor;
a row exists iff the hour had samples, even at 0.0 — absent hour = no row, preserving the pooled-bins
semantics). Persisting them meant the engine read each day's raw accelerometer rows ONCE when the
day's data changed, instead of re-reading 60+14 days of them every 15-minute pass — and the derived
motion history survives both an app relaunch and a raw-stream safe-trim. That raw table is gone now,
so those scalars are read-only history: whatever a database already holds still reads back, and
nothing writes new ones.

FER-972 (P-05) adds two more per-night scalars under the same computed-source suffix: `night_dc_ms`
(nocturnal Deceleration Capacity, ms, over the night's main in-bed session) and `night_warming_c`
(distal warming onset→plateau, °C). The nightly pass persists them next to `hrv_lf`; the Sleep /
Skin-temp detail loaders read the points and lazily write-through any night the engine window didn't
cover, so opening those sheets no longer re-reads ~0.5–1 M raw sample rows.

FER-1008 (the Apple-only recovery redesign) adds a **separate** computed partition, a dedicated
Apple-computed nocturnal-HRV source, holding the nightly nocturnal-HRV scalars: `apple_rmssd_night` (the night's segmented RMSSD, ms — written
only when the night is dense), plus `apple_rr_clean_night` and `apple_rr_pairs_night` (the density counts,
written for every processed night). `HealthKitBridge.ingestNocturnalHRV` writes them from the Apple
heartbeat series; `Repository.autonomicTrend` reads `apple_rmssd_night` back to compute the categorical
`AutonomicTrend` (`NocturnalHRV` → `AutonomicTrend`, both pure in `StrandAnalytics`). This partition is
**deliberately distinct** from both the legacy wearable's computed source and raw `apple-health`: the Apple RMSSD-per-night
baseline is a construct of its own and must never be pooled with the legacy wearable's RMSSD or with Apple's SDNN
(three separate baselines — the "own baseline per construct" invariant, FER-629).

**Bookkeeping** — `cursors(name TEXT PK, value INTEGER)`: one-shot flags and forward-only watermarks.
Two name prefixes are contract, `highwater:<stream>` (upload mark) and `read:<stream>` (pull cursor);
they have to differ so the two marks of one stream can't collide.

`deviceId` is the per-source partition key. The app uses `"apple-health"` for imported Apple Health
(the live source), `"strap"` for the band-era history it still holds, `"-noop"`-suffixed partitions
for what it computes on top of each, and `"noop-journal"` for journal answers logged in Cénit — so
per-source pages and cross-source "consensus" views read the same tables filtered by source. On
`hrSample` and `rrInterval` the stored `deviceId` is the integer surrogate from `deviceIdMap`;
everywhere else it is the TEXT label.

The imported partition was labelled after the band's brand until **FER-993** relabelled it to the
neutral `"strap"` (the app ships to the App Store, so the id written into the user's data can't carry
a third-party brand). That relabel is history now — it is baked into the installed database and does
not exist as a step any more — but it explains why the label lives in exactly one row of
`deviceIdMap`: re-pointing millions of sample rows was a single UPDATE. `auto_vacuum=INCREMENTAL`
keeps later deletes reclaimable, and `vacuum()` (off the launch path, gated by a `cursors` flag) is
what returns freed pages to the OS.

**Orphan, deliberately left alone:** `CircadianPhaseStore.swift` still reads and writes a
`circadianPhase` table that no longer exists. Its calls throw at runtime and the app layer swallows
them with `try?`, so «Tu reloj corporal» has read `nil` since the table was dropped. Preserving that
status quo was the right call inside FER-393 (a fix is either retiring the file or recreating the
table, and both are product decisions); it needs its own issue.

### Day-key convention (local civil day)

`dailyMetric.day` (and the additive-totals window behind it) is the device's **local civil day** in
**every** source — on-device computed (the legacy computed partition), Apple Health (`apple-health`), and
imported legacy-wearable history (already local-of-cycle). The local day is derived by shifting the instant by the
device's UTC offset and formatting in UTC — the pure `AnalyticsEngine.dayString(_:tzOffsetSeconds:)` /
`localMidnight(_:tzOffsetSeconds:)` (offset passed explicitly so the math stays testable), the same
trick file-import glue uses with `tzOffsetMin`. Consumers pick "today" by the matching local key
(`Repository.localDayKey`); `IntelligenceEngine` sums steps/calories over `[localMidnight, +24h)`.
This is what makes the evening's strain/steps/HRV/sleep count for the correct day in a UTC− zone
instead of rolling into a "future-in-local" row (FER-226; consumer shielding in FER-224 / FER-228).

This **supersedes the UTC choice of FER-32** (which dated Apple Health by UTC to avoid duplicate rows
on time-zone travel). The cross-zone duplicate is now handled by last-writer-wins on the `(deviceId,
day)` PK — at most one defined seam on a travel day, never a silent duplicate. On update, a one-time,
flag-gated re-bucket (`cursors.dayKeyV2Done`, no schema change) re-groups the bounded recent window
from the still-stored raw streams / Apple Health onto the local day and prunes the spurious
future-in-local rows; days whose raw was already pruned keep their date (accepted seam, no data loss).

---

## 8. Imports (StrandImport)

Imports converge on the *same* store as HealthKit sync, so history lights up instantly:

```
URL (export.xml / export.zip / folder)
  └─▶ ImportCoordinator.detectKind  → .appleHealth
        └─ AppleHealthImporter   → streamed export.xml (aggregated) → AppleHealthImport  → store rows
```

`StrandImport` is **parse-only**; the app's `AppleHealthImport` glue maps the normalized results into
`dailyMetric`, `sleepSession`, `workout`, `appleDaily`, and `metricSeries` rows, then calls
`Repository.refresh()`. Apple Health's `export.xml` is parsed with a streaming reader so
multi-hundred-MB files don't blow up memory.

The prescribed-diet path is a third producer on the same parse-only principle: `DietPlanImporter`
validates an opaque JSON payload — from the BYO-LLM "copy prompt" flow, a future on-device parse,
or manual entry — into a `DietPlan`, which the app maps to a `dietPlan` row (FER-370). The user
brings the JSON in, so Cénit still makes no network call.

Apple-Health sleep STAGES are the live-sync counterpart of the import path (FER-486): `HealthKitBridge`
reads `sleepAnalysis` category samples, and the pure `SleepHKDecoder` (`StrandImport`, the inverse of
`SleepHKEncoder`) groups them into one `CachedSleepSession` per night — gap-based, 1 h threshold —
mapping Apple's deep/REM/core/awake onto the `[{start,end,stage}]` `stagesJSON` the hypnogram already
reads, stored under `deviceId="apple-health"`. So a night that came from Apple (Combined-without-band,
or Apple-Health-only) draws the same per-epoch hypnogram as a legacy-wearable night. The read-model merge
(`Repository.sleepSessions` → `mergeSleepSessions`) gates Apple sleep on `usesAppleHealth` and lets the
band win per night by interval overlap. No migration — the `sleepSession` table already partitions by
`deviceId`.

**Cross-source daily dedup (FER-411).** The Apple Health export often carries the same civil day recorded by BOTH the iPhone and the Apple Watch. The historical fold (`AppleHealthDayAggregator`, `DailyRollup.swift`) sub-totals the **cumulative** types (`steps`, `activeKcal`, `basalKcal`) per `(day, source)` via `SourcedTotal` and, on read, keeps the **single largest-contributing source** of the day (deterministic tie-break by source key) — never the sum across sources. This mirrors the live path's `HKStatisticsCollectionQuery` (without `.separateBySource`), which dedupes cumulative types by source. **Discrete** types (heart rate, HRV, resting HR, respiration, SpO₂) keep averaging cross-source (identical to the live path); *latest-of-day* types take the most recent. An export without `sourceName` folds into one bucket, so it behaves exactly like a single source (values still add up). No migration: it changes the number computed *before* the write; a re-import corrects old days.

**Third-party strength dedup (FER-362, ola 2 · C4).** Apple Health often already holds strength
workouts a user logged in *another* app (Strong, Hevy, Apple's own Fitness) — surfacing those honestly
under Cénit's «Fuerza» dialect risks two failure modes: double-counting a workout the user *also*
tracked live in Cénit (the same session read twice), and two third-party apps each writing their own
overlapping `HKWorkout` for one real session. `StrandImport.WorkoutHealthKitDedup` (pure,
Foundation-only, no `CenitStore`/`StrandTraining` import) resolves both, in order: **echo** drops an
Apple-sourced loose-strength row (sport contains strength/weight/lift/functional) that time-overlaps a
rich `RichInterval` (a completed `StrengthSession`, Cénit-logged or CSV-imported) — the rich session
always wins, since it has the actual sets; **collapse** then keeps only the longest of any cluster of
overlapping Apple **closed**-strength rows (`isClosedStrength`: `TraditionalStrengthTraining`/
`FunctionalStrengthTraining` only — deliberately narrower than the echo heuristic, since it also gates
entry into «Fuerza»). `HealthKitBridge.mapWorkouts` tags every synced `HKWorkout`'s `source` with the
writing app's real name (`"apple-health:" + sourceRevision.source.name`, falling back to bare
`"apple-health"` when HealthKit reports none) — for *every* Apple workout, not just strength, so a run
synced from Strava shows its real origin too. This rides the existing `source` column, no migration:
`upsertWorkouts`' natural key is `(deviceId, startTs, sport)` and `source = excluded.source` updates in
place. `UnifiedWorkoutHistory.merge` maps `WorkoutRow`/`StrengthSession` into the engine's minimal DTOs
and keeps only `survivingRows`; `UnifiedWorkoutHistory.fuerzaEntries` is the read-time gate that
actually admits a surviving third-party envelope into «Fuerza» — Apple origin
(`WorkoutSource.classify == .apple`) + closed-strength sport + a plausibility guard (span > 0, ≤ 24 h,
kcal/HR in a human range) that **discards** — never clamps — a corrupt envelope. A user toggle
(`DataSourcesView`, `workouts.showThirdPartyStrength`, on by default) hides the third-party half of
that gate without touching the rich-session half. This is a distinct mechanism from the Watch-mirror's
own single-`HKWorkout` invariant (§5, `HKMetadataKeyExternalUUID`) for Cénit's *own* write-back, which
is never read back here since `HealthKitBridge.readPredicate` already excludes `HKSource.default()`.

The **recovery** counterpart for a band-less night used to be an **estimate computed read-time**
(FER-153): `AppleRecoveryEstimator` over `apple-health` daily rows, kept out of
`days`/`displayDays` and surfaced only on today's display. **That production path is retired**
(Frente A · R4, FER-1008): `Repository.assembleDashboard` hardcodes `recoveryEstimates` to `[:]`, so
`isRecoveryEstimated` is always false and the `~N` estimated-recovery UI cascade no longer renders.
Today shows sleep + the autonomic trend (`AutonomicTrend` from nocturnal Apple RMSSD) instead. The
`AppleRecoveryEstimator` type, its tests, and `Repository.appleRecoveryEstimates(...)` were **deleted**
in the Frente D dead-code sweep (FER-1003). No column, no migration.

---

## 9. Analytics (StrandAnalytics)

There is no per-day orchestrator. Each engine below is a pure function called directly by whichever
surface needs it — `Repository`, `HealthKitBridge`, `AppModel` or a screen — over the Apple Health rows
already in the store. `AnalyticsEngine` itself is now only the civil-day key and the sleep-stage codec
(FER-387).

- `strengthSession.strainSource` / `sessionRpe` / `sessionRpeSource` / `trimpPerAU` / `source` / `title` /
  `programWeek` / `deload` (v42, ola 1 · FER-324) — where the session's strain came from (`hr` measured,
  `rpe` estimated: the label the receipt and Tendencias must show), the one-tap session effort (6–10,
  NULL = never answered, never defaulted), whether it was tapped or accepted as the suggested prefill, the
  estimate's scale, the import provenance (`strong`/`hevy`/`cenit`, NULL = Cénit), and the program
  week / light-week flag (1 = a progression boundary). All nullable, appended via `addColumnIfMissing`.
- `routineExercise.progressionUseRPE` (v42, DEFAULT 0) — the «Según reps en reserva» rhythm; off in every
  pre-existing routine by construction.
- `routineSet.mode` / `setEntry.mode` (v42) — `SetMode` (`standard`|`amrap`|`drop`), NULL = standard; an
  axis ORTHOGONAL to `SetKind` so the app's `kind == .work` filters stay untouched. A drop is its own
  `setEntry` right after its mother set by `position`, no FK.
- `program` (v43) — the one active program (PK `id = 'active'`): `name`, `weeks`, `startTs`, `deloadRule`,
  `endMode`, `templateId`, `createdTs`. The current week is DERIVED from `startTs` and the weeks actually
  trained (`ProgramCalendar`, E10), never stored. Deleting the row leaves routines and the weekly schedule.
- **Sleep phases** come from Apple Health, decoded by `SleepHKDecoder` in `StrandImport`. The own
  stage classifier was **deleted** (FER-385): it scored nights offloaded from a device the app no longer
  has, and had no call site outside its own tests. Only `StageSegment` survived, in its own file — it is
  the on-disk JSON shape of a night's timeline, hand-mirrored in `StrandImport` and parsed by hand in
  `SleepDetailScreen`, so its three fields are a byte contract in three directions at once.
- **`HRVFreqDomain`** (FER-669) computes frequency-domain HRV (LF/HF/total power, ms²) from an R-R
  series via the Lomb-Scargle periodogram (Lomb 1976; Scargle 1982) on the uneven tachogram — no
  resampling — span-gated per Task Force (1996). **Additive**: feeds no recovery/strain/sleep output.
  Surfaced in the HRV detail (FER-702): the nightly `Bands` are computed over the SAME in-bed
  session R-R as `avgHrv` (coherent by construction), the app persists the three powers to
  `metricSeries` under a legacy computed-source suffix, and `HRVSpectralBaseline` labels each band vs "your normal" by reusing
  `Baselines.foldHistory(logDomain:)` + z-score (log-normal HRV powers, Plews 2013) — no new estimator.
- **`RecoveryScorer`** is down to two live pieces (FER-387). The `0–100` composite was **deleted** — it
  had no call site, and both surviving import routes write `dailyMetric.recovery` as `nil`, so it was
  never computed nor shown; `Preparedness` is the hero. What remains is the nocturnal resting-HR
  estimator (the minimum of qualifying five-minute bin means, not the lowest beat) and the three band
  cuts that `TrainingRegulation` and `ReadinessEngine` name by symbol.
- **Baseline recalibration (FER-677).** `ProfileStore.baselineEpoch` (a `YYYY-MM-DD` local day-key in
  UserDefaults, with one level of undo via `previousBaselineEpoch`) cuts every nightly baseline fold:
  `Baselines.foldHistory(_:epoch:cfg:)` drops nights with `day < epoch` before the replay (delegating to
  the value-only fold, so all its invariants hold). `IntelligenceEngine` applies it to all five baselines
  (HRV/RHR/resp/temp/efficiency) and pass-1 — so recovery re-anchors from the epoch. It is
  a user setting, not derived data: **no GRDB schema**. `nil`/`""` epoch = no cut (byte-identical to before).
- **`AppleRecoveryEstimator`** (FER-153) scored an **estimated** recovery (the `~N`) for band-less nights
  from Apple's SDNN. **Retired and deleted** (Frente A R4 retired the UI; Frente D deleted the type) —
  replaced by sleep-as-hero + the categorical `AutonomicTrend` read, which never shows a 0–100 recovery
  (Task Force 1996; Shaffer & Ginsberg 2017). Pure + DB-free; surfaced read-time (see §8), not persisted.
- **`CyclePhaseEngine`** (FER-672) estimates the current menstrual-cycle phase (follicular-lean vs
  luteal-lean) from the nightly `skinTempDevC` Cénit already persists (+ resting HR corroboration; HRV as
  conditional confidence only, decision H1). Robust z-index over the trailing window (median centre,
  IllnessWatch robust σ), ≥42-night gate, states `.learning` / `.noClearPattern` / `.estimated`. Pure,
  DB-free, **on-the-fly — no persistence, no migration, no new decode**. Opt-in, surfaced only in the
  Experiments sheet (Ajustes), off by default. Wellness / self-knowledge only, retrospective (temp
  confirms a phase with 1–3-day lag), never fertility/ovulation/contraception/diagnosis. Weights + gate
  are product-calibration knobs, not validated; see docs/ANALYTICS.md for citations.
- **`SourceLens`** (FER-623 / FER-631) collapsed to a **single-source cleaner** in the band demolition
  (F6, «la banda nunca existió»): the multi-source masking machinery (`maskForBaseline` / `maskHrv` /
  `keep:`) is gone, replaced by two **unconditional** helpers. Every row is now an Apple row, and Apple's
  `avgHrv` is **SDNN** (all-day total variability) while the recovery/readiness/Body-Age engines were tuned
  on the band's **RMSSD** (vagally-mediated, sleep-windowed) — different time-domain constructs with no
  published conversion (RMSSD≠SDNN — Task Force 1996; Shaffer & Ginsberg 2017), plus measured RHR/resp/stage
  offsets (FER-629). Folding a raw Apple SDNN into a band-domain baseline reintroduces the FER-519
  contamination bug, so before any such fold the app clears the offending columns: `clearBandColumns(_:)`
  nils **every cross-source column** (`avgHrv`, `restingHr`, `respRateBpm`, `deepMin`/`remMin`/`lightMin`,
  `skinTempDevC`) and `clearBandHrv(_:)` nils **only** `avgHrv`; a cleared column reads as a "missing" night
  to the skip-and-hold folds, never a zero. The one HRV number Today shows does **not** come through here —
  the categorical `AutonomicTrend` reads real nocturnal **RMSSD** (`apple_rmssd_night`, see §7) via
  `SourceFusion.autonomicTrend`, which never touches `avgHrv`. Pure + DB-free; the z-score stays the common
  currency, raw ms are never compared across constructs.
- **`StrainScorer`** integrates the day's HR window into a `0–21` cardiovascular load (Tanaka HRmax
  from age unless overridden).
- **`WorkoutDetector`** was **deleted** (FER-387): it required a gravity series whose table was dropped
  in migration `v37`, so it could only return an empty list. Apple supplies `HKWorkout` from the Watch
  and `AppleLoadEstimator` turns those into the day's load. **`Calories`** survives and is live — Keytel
  (2005) over heart rate, revised Harris–Benedict at rest, and a compendium MET value when a strength
  session captured no heart rate; its output is mirrored to Apple Health as active energy.
- **`Baselines`**, **`HRZones`**, **`CorrelationEngine`**, **`ComparisonEngine`**, and
  **`BehaviorInsights`** supply rolling baselines, zone math, and cross-metric/behaviour insights.
- **`SleepRegularity`** (FER-218) scores schedule consistency from a rolling window of nights: the
  circular standard deviation of the mid-sleep point (Wittmann et al. 2006; Mardia & Jupp 2000) plus the
  weekend "social-jetlag" shift. Pure + DB-free like the rest; the app feeds it onset/wake out of
  `repo.sleeps`. The SD (minutes) is the validated figure; the 0–100 score is presentation only.
- **`RecoveryForecast`** (FER-188) projects tomorrow's recovery one day ahead from the recent
  recovery series — a damped level+slope trend plus a bounded sleep-debt drag and an optional
  acute session-strain drag (FER-442, for the post-session "tomorrow ~X%" line in the strength
  summary; direction per Stanley 2013) — returning an `estimate` with a deliberately wide
  confidence range, or `nil` below ~two weeks of base (the UI then hides the block). A trend
  projection, never a guarantee; simple by design per the short-term autoregressive-forecasting
  evidence (De Sabbata & Simonini, *J Healthc Inform Res* 2025). Pure + DB-free; the app feeds it
  the recovery column out of `repo.days` (two consumers: the Recovery detail and the strength
  summary cost block).
- **`InsightEngine`** (FER-290) is the single orchestrator behind the redesigned Coach ("el Bucle"):
  it takes data already read from the store (`DailyMetric`, logged behaviours, sleep sessions) and
  runs a catalog of detectors — each a thin wrapper over one of the engines above (`BehaviorInsights`,
  `CorrelationEngine`, `Baselines`, `ComparisonEngine`, `RecoveryForecast`, `SleepRegularityIndex`,
  `ActivityCostEngine`, `ReadinessEngine`, `FitnessAgeEngine`, plus a sleep-debt aggregate) — and
  returns ranked `Insight`s with es-MX templates. It **re-implements no math**; its only new logic is
  statistical hygiene: every inferential detector feeds ONE Benjamini-Hochberg family
  (`MultipleComparisons`) so a finding is "significant" only when its FDR-adjusted q-value clears α
  alongside per-side sample and effect-size floors. A synthetic suite proves planted effects are
  recovered and pure noise is not (family-wise false-positive rate held near α). The LLM step
  (issue E) only rewrites the templates — it never produces a figure. Pure + DB-free. The behaviour
  family accepts a per-behaviour *eligible universe* (`Inputs.eligibleDaysByBehavior`, FER-385) so a
  source whose absence means "unknown" rather than "didn't happen" — diet adherence — only contrasts
  the days it was actually tracked; journal behaviours pass none and keep absence = "without".

- **`ExperimentVerdict`** (FER-307) is the N-of-1 "Prueba" engine behind the redesigned Coach: it
  judges whether a candidate lever (a logged behaviour × an outcome) *reproduced* prospectively over
  an experiment window. It re-implements no math — it delegates to `BehaviorInsights.effect` (Welch +
  pooled Cohen's d + the `minGroup` floor), comparing the window's adherent days (derived from the
  existing journal) against the user's baseline, and classifies a `Verdict` (`sustained` /
  `notSustained` / `insufficient`). A `sustained` verdict promotes the lever candidate→proven, which
  `InsightEngine.promoteProven` then projects onto the engine's output (the engine stays stateless;
  "proven" lives in the `experiment` table, not on the `Insight`). Pure + DB-free.

- **`TrajectorySimulator`** (FER-311) is the goal simulator's projector: it extends a goal metric's
  daily series over an N-day horizon as two paths — "como vas" (the trend) and "si cambias X" (the trend
  plus a proven lever's measured effect) — inside a confidence band that grows with √h. The trend is a
  **damped** level+slope (Gardner–McKenzie 1985) so long horizons plateau instead of extrapolating in a
  straight line; it reuses `RecoveryForecast.olsSlope`/`sampleSD` and is **metric-agnostic** (the app
  passes the focus series, generous `bounds`, and a *signed* `leverDelta`, so a higher-is-better metric
  and a lower-is-better one like resting HR share one projector with no special case). Returns `nil`
  below ~two weeks of base (the screen hides the chart). It never projects performance, only the
  measurable signal. Pure + DB-free.
- **`StressEngine`** (FER-376) is the intraday autonomic-activation ("stress") engine: a `0–3` curve
  for the current day from beat-to-beat RR, normalized against a **personal waking reference** (robust
  percentile RMSSD anchors over the recent ~7 days of *waking* buckets — high RMSSD = calm = 0, low =
  activated = 3, clamped). It reimplements no HRV math — it delegates per window to `HRVAnalyzer`
  (RMSSD, Task Force 1996; Malik 1989 cleaning). Unlike the daily `StressModel` it is **relative to the
  person's own waking day** (the daily resting/sleep baseline would read "maxed out all day"); noisy or
  active windows (HR-reserve gate, analogous to Firstbeat excluding activity) and excluded spans
  (sleep/movement) return `nil` ("no reading"), and a short history yields no reference (cold start),
  never a min-max fallback. The reference is computed **on the fly** from the already-stored
  `rrInterval` rows (no new migration, mirroring how the strain curve recomputes from `hrSample`);
  persisting a summary for performance and cross-day patterns is deferred to FER-378. Pure + DB-free.

Because the engine never touches the database, the same code runs over live-collected streams,
backfilled streams, or imported data interchangeably. **All derived values are approximate.**

---

## 10. Presentation (the app + CenitDesign)

The `Cenit` app shell (under `CenitApp/App/`) builds a single `AppModel`, injects it (`.environment`)
plus `Repository`, `ProfileStore`, `BehaviorStore`, `GoalStore` (the Bucle's goal — a single
metric+date preference in `UserDefaults`, not a DB table, FER-311), `HealthKitBridge`, `AutoBackup`,
`TabRouter`, and `MediaDownloadCoordinator` as environment objects (`CenitApp.swift`), and presents the
shared screens under `Cenit/Screens/` (Today, Breathe, Intervals, Compare, Sleep, Trends,
Workouts, Health, Apple Health, Data Sources, Settings, Support). There is no `LiveState` injection
(the BLE connection snapshot type was removed with the band amputation), and no separately reachable
Automations screen. The home / lock-screen widgets live in `CenitWidgets/`.

**Inject (hot-reload).** The app target links the third-party `Inject` package (`project.yml`) for
Debug UI hot-reload with InjectionIII / InjectionNext. In **Release** the library is a **no-op**: the
`-interposable` linker flag is Debug-only and the `.enableInjection()` / `@ObserveInjection` hooks
compile away. **Verified (2026-07-20) on an unsigned Release iOS build**: the code is statically linked
in (Inject symbols appear in `nm`, and one `InjectionIII` path string survives), but it pulls **no
external dylib** (`otool -L` shows only system libraries) and **zero `enableInjection` strings** remain —
present but inert, as designed. It is the only non-first-party dependency of the shipping binary; the
posture is "accept and document," not remove (a Debug-only link is not cleanly expressible in xcodegen
and `#if DEBUG`-guarding ~46 call sites is churn for a cosmetic gain). Re-check with `nm`/`strings`/
`otool -L` on a Release binary if App Review ever objects.

**Dormant / retired surfaces (post band amputation).** (a) `IntelligenceEngine.analyzeRecent` is a
no-op under the pinned `.appleHealthOnly` mode: it guards on the pinned source-mode and returns early
(`IntelligenceEngine.swift`), so the ~15-minute offloaded-night scoring loop does not run today.
(b) The `~N` estimated-recovery display is **retired from the production dashboard path** (Frente A ·
R4, FER-1008): `assembleDashboard` leaves `recoveryEstimates` empty, so the estimated badge/numeral
cascade does not render. `AppleRecoveryEstimator` and `Repository.appleRecoveryEstimates(...)` were
**deleted** (Frente D / FER-1003) — they no longer exist in source.

Screens bind to `Repository`'s published `days`/`sleeps` caches (refreshed on data change, not on the
~1 Hz stream). The launch refresh runs in **two passes**: a ~90-day *first-paint* pass that publishes
immediately (`loaded == true`, `fullyLoaded == false`) so Today renders without waiting for the full
history, then a full pass whose merge work runs **off the main actor** (`Repository.assembleDashboard`,
nonisolated) and publishes the identical final dashboard (`fullyLoaded == true`). Each pass reads the
store through ONE `CenitStore.dashboardSnapshot` call — a single read transaction / WAL snapshot
(FER-970 · R-03) instead of ~13 sequential actor reads — so the published dashboard is cross-table
consistent by construction; the only separate read left is the skippable Apple workout-HR phase (R-01). A monotonic
generation counter makes the most recently started refresh the only one that may publish, and a
first-paint pass can never overwrite a fully loaded dashboard (`Repository.shouldPublish`). **Rule:**
anything that *persists* a value derived from `repo.days` — `IntelligenceEngine.analyzeRecent`
baselines, `Repository.closeDueExperiment`, the restore offer — must gate on `repo.fullyLoaded`;
pure display readers may see the short window transiently and self-correct on the full publish.

`IntelligenceEngine.analyzeRecent` — the ~15-minute scoring loop — is **incremental per day and
off-main** (FER-868). Each pass takes ONE `CenitStore.streamDayCounts` snapshot (COUNT(\*) per local
civil day per raw stream; sound because the stream writers only `INSERT … ON CONFLICT DO NOTHING`,
never UPDATE — a backfill that fills a gap moves the COUNT even when it doesn't move MAX(ts), and a
safe-trim lowers it) and compares each night's window signature (`AnalysisScheduler`, pure, in
`StrandAnalytics`) against an **in-memory** cache: clean nights replay their cached pass-1
`NightResult` with zero store reads; only dirty nights (plus today, always) pay the 8 stream reads +
`analyzeDay`. Pass 2 — the baseline seed + `recomputeRecovery` — still runs over ALL nights
unchanged, so the published scores are identical to a full pass; the upserts also still write the
full window (the detected-workout prune deletes-and-reinserts it). The cache is not persisted: a
relaunch costs one full first pass, and `force` / any context change (profile, tz, mode, baseline
epoch) resets it. The heavy body is a `nonisolated static runAnalysis(_:cache:store:)` run on a
`.utility` detached task — same pattern as `Repository.assembleDashboard` — with all repo-derived
inputs snapshotted contiguously on the main actor before the hop (FER-177/519); `analyzeRecent`
itself stays a thin `@MainActor` wrapper (guards → snapshot → hop → publish). The daily motion
derivatives it persists (`motion_intensity`, `act_hNN`) are described in §7 "Generic metric series".

Screens render with `CenitDesign` components — `RecoveryZoneGauge`, `Hypnogram`,
`TrendChart`, `TrajectoryChart` (the goal simulator's two-path + confidence-band plot), `Sparkline`,
`YearHeatStrip` — over the `StrandPalette` tokens. `AppModel` also hosts
the opt-in, on-device behaviours (HR smoothing, illness/strain early-warning, stress nudges, HR-zone
haptic coaching, double-tap actions, wrist-wear automation, smart alarm) — all default-off and all
computed locally.

### Network exceptions (opt-in, off by default)

Cénit is offline by construction (§11.1) with exactly **one** deliberate, user-controlled exception,
living in `Cenit/` (never in `Packages/`, which stays 100% offline so `swift test` over packages
is hermetic in CI):

- **Exercise media** (`Cenit/Media/`, FER-722/786) — thumb/video-loop cache from ExerciseDB.
  **Dormant since FER-398:** its Settings card is gone, its preference is neither persisted nor
  migrated, the launch-time bulk download was removed, and `MediaDownloadCoordinator.isEnabled`
  returns `false` unconditionally. Both entry points (`bulkDownloadThumbsIfNeeded`,
  `loopIfNeeded(for:)`) still guard on `isEnabled` before touching `URLSession`, so the app now makes
  zero network requests by construction, not by convention. FER-919 revives it with first-party art. Media downloads once per exercise into a `MediaCache/{thumbs,videos}/` folder
  under `Application Support/Cenit/` (see §2) — presence of the file on disk
  **is** the "downloaded" record, no GRDB table — and stays there (offline-readable) until the user taps "Borrar
  media descargada"; turning the toggle off stops future downloads but never deletes the cache. Since
  FER-786 the download is a **plain GET of each exercise's baked `gifUrl`** (native ExerciseDB id, from
  the FER-779 catalog) off the public CDN `static.exercisedb.dev` — **no runtime name lookup, no API
  key** (the old `ExerciseDBClient`/RapidAPI path and its `EDBApiKey` were retired). An exercise with
  no `gifUrl` is a miss → the YouTube hand-off fallback stays.

(The former BYO-key external AI Coach was removed with the band-era cleanup.)

### The «Instrumento diurno» theme (single warm day paper)

`CenitDesign` carries a second, light-mode visual language («Instrumento diurno», warm paper) whose
`InstrumentoTheme` role struct is injected through the `\.instrumentoTheme` Environment key. Screens
anchor it to the single day paper, `InstrumentoTheme.base`, via `.instrumentoTheme(.base)` (which also
sets `\.instrumentoFlat`, so shared chart components drop the legacy dark-system glow on paper). The
theme does **not** change with the clock.

FER-132 originally varied the theme by the device clock — a 60-second `InstrumentoThemeDriver`
interpolating all seventeen roles between dawn/day/dusk/night anchors in the perceptual **OKLab** space,
overridden app-wide by `View.instrumentoThemeByHour(solar:)`. **FER-398 retired that engine:** the owner
found the dimmed night parchment (`#A39C8F`) read as "the brightness dropped" rather than warmth, and
the design research placed time-of-day colour in *content*, not chrome (and Apple's convention is a
stable, user-controlled appearance). The app is now a single warm light paper at every hour, on every
screen — far less machinery (no anchors, no per-minute interpolation, no timer).

What survives in `InstrumentoThemeEngine.swift` is load-bearing for the parts that still encode the day:
`InstrumentoThemeEngine.localHour(of:calendar:)` and the injected `SolarWindow` feed the «Hoy»
`DiurnalDial` (its now-dot, day arc and sleep band still track the real clock — time as *datum*, not
tint), and the pure **OKLab** colour math (Ottosson 2020) backs the paper gradient
(`paperHi`/`paperLo`/`inkDim`), `DiurnalDial.dayGold`, `ReferenceRange`, and the AA-repairing
`positiveText`/`negativeText` (the base anchor's hues clear WCAG AA on its paper; pinned in
`InstrumentoThemeEngineTests` / `FitnessAgeContrastTests`). **Package purity:** sunrise/sunset
(`StrandAnalytics.SolarClock`, FER-133) is consumed by **injection** of a plain `SolarWindow` value,
never imported — `CenitDesign` remains the dependency-free leaf of the package graph, 100% offline
(`Date`/`Calendar` only).

### Two-mode color resolution (modo oscuro — épico FER-343, cimiento A1/FER-345)

Since A1, `LiquidColor`'s public tokens keep their name and `Color` type but resolve by `ColorScheme`:
each is built by `LiquidTheme.dynamic(light:dark:)` over a platform dynamic provider
(`UIColor/NSColor(dynamicProvider:)`, behind `#if canImport(UIKit) && os(iOS)` / `AppKit` — the package
stays UIKit/AppKit-free by import; watchOS falls to a light-only `#else` because the wrist keeps its own
`LiquidOLED` vocabulary, D1=a). The deterministic source of truth for tests and the Metal hero is
`Color.resolved(at:)`, which sets `EnvironmentValues.colorScheme` explicitly before `resolve(in:)` — a
dynamic color does NOT resolve dark from the ambient appearance on a headless macOS test host, only from
an explicit scheme (`LiquidThemeResolveTests`). A single global switch `LiquidTheme.oscuroHabilitado`
(default `false`, read inside every provider) keeps everything resolving light — in every process, app and
widgets — until A3 flips it atomically. Light-mode values are byte-identical to the old static hexes
(`LiquidThemeRegresionClaroTests`), so A1 changes nothing visible on its own.

Contrast is mode-aware through one sanctioned helper, `LiquidColor.contrastTuned(_:against:)`: it darkens a
data hue against light paper in `.light` (the old `OKLab.darkened`) and keeps or lightens the hue against
the dark floor in `.dark` (`OKLab.lightened`, mirroring `EntrenarHilo.word(sobreOLED:)`) — because
`OKLab.darkened` is a light-only algorithm (darkening on black destroys contrast). `tonoCampo` is likewise
mode-aware. The `no-raw-contrast` gate forbids raw `OKLab.darkened/lightened(` outside `LiquidContrast.swift`
/ `LiquidColor.swift` (Instrumento legacy exempt), so no screen can re-introduce a light-only anchor. The
Apple Watch keeps `LiquidOLED` unchanged (`LiquidOLEDIntactoTests`): dark data twins are iPhone-only (D1=a).

**The Today hero renders on two backends (FER-10 Phase A → FER-13 Phase B).** «El Ecosistema» is the
only place in the design system with a GPU path. The two share a **choreography** contract, not a
pixel one — Core Graphics and Metal antialias differently, and nothing asserts they rasterize
identically:

- `EcosistemaSimulacion` (pure, Foundation-only) owns the physics. `particula(dir:indice:…)` is
  deliberately stateless and derived only from *(direction, frame, t)* — that is what makes it
  expressible as a shader.
- `EcosistemaSimulacion.plan(t:escena:)` (also pure) turns an instant into an ordered list of
  `Trazo` values — clouds, discs, rings, halos, labels — speaking in *tints* (roles), never `Color`.
  This is the single choreography; `EcosistemaPlanTests` is its contract.
- **Backend A — `EcosistemaCanvas`** walks the plan with `GraphicsContext`. It is the path for
  macOS/watchOS, previews and deterministic QA renders, and the fallback whenever Metal is not
  available.
- **Backend B — `EcosistemaMetal` + `EcosistemaShaders.msl`** (iOS only) walks the same plan and
  encodes *instanced* draws: one cloud is one draw and the vertex shader derives each particle from
  its index, so ~850 particles never cross the CPU/GPU boundary as data. Orbital **labels stay on the
  Canvas** on top — text remains real text with the design system's typography.
- **Matter interpolates; it never crossfades (FER-16 / FER-19).** State transitions inside the hero
  are *morphs over one particle population*: `Trazo.nubeMorfo(a:b:mezcla:)` evaluates the same
  Fibonacci direction `i` under configuration A and B and lerps position/size/alpha per index —
  `EcosistemaSimulacion.particulaMorfo` is the pure spec, `vsNubeMorfo` its GPU port (two `NubeU`
  buffers; `mezcla` rides the former `_pad1`, stride stays 112). At `mezcla` 0/1 the morph is
  bit-equal to the plain cloud — that equality is the tested contract. Cross-count morphs
  (orb ↔ moon) stay out of scope until an index-remap policy exists (C.3).
- **Accretion is unified matter (FER-20 · C.3).** While calibrating, the 34 spirals do not die in
  midair: each mote lands exactly on `particula(dir, embryo, t)` — its death is the birth of sphere
  matter. The 34↔300 remap policy is deterministic: spiral `i` on fall-cycle `c` feeds fibonacci
  index `(i + 34·c) mod nLiquido`, where `nLiquido` is the liquid fibonacci prefix
  (`nivel = noche/total`, 8 % floor) — accreted matter IS the accumulated liquid, never vapor.
  Cross-count lives in the choreography (`planAcrecion` + `motaAcrecion`); the `nubeMorfo` law stays
  same-count. The embryo shares the verdict sphere's config (`nEsfera`, `centro`): cross-day
  continuity by construction. Under Reduce Motion, only the settled embryo. If calibration completes
  with the screen open, the embryo **graduates** live into the verdict orb via a same-count
  `nubeMorfo` (`Escena.graduacion`, anchored by the view) — the two decision spheres never appear.
- **Cross-count fusion decomposes into same-count morphs (FER-27).** The C.2 law — `nubeMorfo` requires `a.n==b.n && a.paso==b.paso` — stays sacred. The eclipse's 2→1 need (two sentinels, `nGuardian` each, becoming one front) is met not by relaxing that precondition but by recognizing an equal-count 2→1 fusion as the **superposition of two same-count morphs** onto a shared destination cloud: `(A_j,B_j)→front_j`, remap identity. At `mezcla=1` both `nGuardian`-clouds coincide on the front (one body, no seam); at `mezcla=0` each is bit-equal to its orbiting sentinel; instance count is unchanged, so matter is conserved. General cross-count (`floor(i·nA/N)`) remains the documented reserve policy, unimplemented until a real `nA≠nB` case exists. Shader, Metal and uniforms are untouched — the whole change lives in the plan.
- **The moons come forward; the orb never splits (FER-22).** The tap choreography inverted after
  the epic: the two decision moons — which already ARE the signals — travel to the stations and
  grow into the gauges (`nivelMezcla` = apertura reveals the liquid en route), while the verdict
  orb recedes (small, dim, `radioOrbeFondo`) yet never disappears or splits. The sentinels are TWO
  moons by birth (opposite phases on the outer orbit) — there is no «guardian that splits». The
  connections live in BOTH states with two grammars: a flowing mote cord (deciders feed the
  verdict; red when out of range) and a static dotted gaze per sentinel (watching transfers no
  matter; an amber pulse runs the line only when alerting). In Atención the orb itself absorbs the
  amber (`particulaAmbar`, owner's call). Sphere-pair fusion, its convergence morph and the
  contact flash are gone; `nubeMorfo` survives solely for the embryo graduation. Numbers are solid
  type again — matter draws matter, ink writes data.
- **Sheet↔hero continuity is a two-halves illusion (FER-21 · C.4).** Tapping «Cómo llegué a esto» opens the acta
  sheet on pure paper (FER-23, owner): both the hero exhalation and the acta constellation
  (`LiquidSiembraMotas`, kept in the DS as an opt-in) were retired — the two-halves illusion is
  gone, «how I got here» carries no particles from either side.
  Text-is-text stays law: only THE numeric datum is ever written in motes, and this sheet has none.
  Reduce Motion (system flag or the preview override) disables both halves.
- **Nothing derived from the app's clock reaches the GPU as `Float`.** The hero's `t` is
  `timeIntervalSinceReferenceDate` (~8.07 × 10⁸ s); at that magnitude a `Float` ULP is tens of
  radians, which would freeze the rotation for ~53 s at a time and collapse 300 jitter phases into
  6. Every angle is reduced to `[0, 2π)` in `Double` first (`EcosistemaSimulacion.fase`) — exact,
  since sine and cosine have period 2π.
- The shader ships as **`.msl`, not `.metal`, on purpose**: Xcode compiles any `.metal` it finds,
  which would make the separately-downloaded **Metal Toolchain** a hard requirement to build the app
  at all. It is compiled at runtime, in the background, and until it is ready (or forever, if it
  fails) the Canvas draws. Degrading is a designed state, not an error.

**Hoy's background is a second, independent Metal layer: the atmosphere (FER-118).** The Today
screen sits on pure white and the only thing alive behind the glass is *dust* — a full-screen
field of particles that drift upward, breathe, take the verdict's colour and shift 22 % with the
scroll (parallax). The hero is **not** part of the background: it scrolls with the content.
- `PolvoSimulacion` (pure, Foundation-only) is the spec: particle `i` at time `t` is derived from
  its index with an integer Wang hash (`hash(i, k)`), never from a stored list — the same
  index-derived discipline as the hero. Every tunable lives in `PolvoSimulacion.Fisica` and travels
  to the GPU in `EcosistemaPolvoU` (mirrored field-by-field by `PolvoU` in `EcosistemaShaders.msl`,
  stride asserted in `EcosistemaPlanTests.testLayoutDeLosUniformes`); the shader owns no numbers.
- **Backend Metal — `EcosistemaPolvoRenderer` + `vsPolvo`**: one instanced draw of `n` quads
  (`n = area / 234 pt²`, clamped 600…2000), sharing `EcosistemaMetal.Recursos` (one shader
  library, compiled once). `Recursos.polvo` is *optional on purpose*: it is built outside the
  hero's `guard` chain, so a pipeline failure only sends the dust to the Canvas and the hero keeps
  its Metal. (The library is still one file: a compile error in `vsPolvo` degrades both — that is
  what the offscreen render tests and the DEBUG assertion in `biblioteca(_:)` are for.) The verdict
  crossfade (1.6 s) is a lerp of the palette *inside the renderer* — a uniform cannot be animated
  by `withAnimation`.
- **Backend Canvas — `LiquidAtmosfera.lienzoCanvas`**: the same spec at half the count and 12 Hz
  for macOS/watchOS, previews, deterministic renders (`liquidMotionDisabled`) and any device
  without Metal.
- **Clock and pause.** A single `TimelineView` at 20 Hz (`LiquidMotion.intervaloAmbiente` — the
  drifts are ≤ ~7 pt/s, i.e. ≤ 0.35 pt per frame), paused under `liquidAmbientPaused` (sheet open,
  background, onboarding), when the tab is hidden (`AtmosferaEstado.visible`) and under Reduce
  Motion (`still`: no time, no breathing, no parallax — but every particle drawn). Its `t` is
  **session time** (`Date().timeIntervalSince(inicio)`), never the reference-date clock, so a
  `Float` resolves it comfortably (see the ULP note above).
- **Parallax without recomposing `TodayView`.** The screen owns an `@Observable`
  `AtmosferaEstado` (`desplazamiento`, `visible`); the scroll's existing offset reader writes
  `desplazamiento` (≥ 0, the pull overscroll does not count) and only `LiquidAtmosfera` reads it —
  so a scroll frame invalidates the background alone. The `MTKView` is `isPaused` +
  `enableSetNeedsDisplay` and redraws on demand when the offset changes, at scroll speed, while
  the ambient clock stays at 20 Hz.

### Design-system enforcement (gates, baseline, censo) — épico FER-261

> Regla añadida A1/FER-345: **`no-raw-contrast`** — `OKLab.darkened/lightened(` crudo solo en `LiquidContrast.swift`/`LiquidColor.swift`; el contraste de dato pasa por `contrastTuned` (mode-aware). Cuatro patas + paridad, como el resto.

`CenitDesign` is the source of visual truth **in fact, not just on paper**, because a tooling layer
stops the gated debt classes from growing (a PR that sabotages the tooling itself is caught by its
own diff in review, not by the tooling — no text-level check can guard its own executor):

- **One linter, three legs.** `Tools/check-design-drift.py` (pure Python/regex, milliseconds) runs
  the same rules in the pre-commit hook, `Tools/verify.sh quick` and `.github/workflows/design-lint.yml`
  (ubuntu). Rules cover literals (hex, font, radius, opacity, shadow, spacing), copy (em-dash),
  sheet-glass, **retired-generation call-sites** (`no-legacy-api`) and the escape hatch itself
  (`token-exempt` is ratcheted debt). Widgets/Watch are carved out of the two FER-263 rules in
  `check()` itself (FER-219: fixed system geometry, `InstrumentoTheme` is canonical there).
- **One baseline, merge-written.** `Tools/design-drift-baseline.json` freezes debt per
  `{rule: {file: count}}`. `--write-baseline` merges per FILE (partial scans keep un-walked budgets;
  deleted files drop; corrupt JSON is refused) and a count can only go down: the `baseline-monotony`
  job compares the PR's JSON against the PR's base **running the guard script from the base commit**,
  and the only legal raise is a dedicated baseline-only PR carrying the owner-applied
  `baseline-alta` label — both conditions machine-checked, so a PR with code can never bless itself.
- **Parity is a check, not a hope.** `Tools/check-gate-parity.py` parses the three legs and fails
  CI (and `verify.sh`) if they diverge from the machine-readable gate matrix in
  [`docs/design-system/CONTRATO.md`](design-system/CONTRATO.md) — including any `--baseline`
  pointing away from the canonical JSON. The contract doc (hand-written; DESIGN.md is generated) also
  defines the exemption taxonomy, the ×3 rule, the collision-arbitration policy and the legal-raise path.
- **Census and catalog.** `Tools/DesignCensus/` is an ISOLATED swift-syntax executable (never a
  dependency of `CenitDesign`, never in CI's hot path) that regenerates
  `docs/design-system/CENSO.md`+`.json` — 8 dimensions, evasion sieve, exemption taxonomy, collision
  candidates — re-run before each quarterly batch. `CenitDesignTokens` additionally emits the Liquid
  dictionary and the component index `docs/design-system/CATALOGO.md`, guarded by `design-tokens.yml`.
  `DesignDriftTokenTests` is the value oracle (token == wrapped literal); the `ImageRenderer`
  harnesses stay harnesses, never pixel assertions.

### Enseñanza: el registro y el gate (épico FER-428 · L4/FER-430)

Cada funcionalidad declara **una vez**, en `Packages/CenitEnsenanza`, cómo se enseña: id estable
(`FuncionalidadID`, también el `id` de su tip), pestaña, requisitos declarativos (`.watch`,
`.noches(n)`…), piezas (`.vacio`, `.tip`, `.hito`, `.ayuda`, `.novedad(version, mayor:)`,
`.gestoConBoton`) y versión `desde`. El registro guarda texto (claves `ensenanza.<id>.*` del
catálogo de la app) y rutas (la pestaña); nunca lógica ni estado. Un id nunca se renombra.
**Excepción documentada (L8/FER-437):** la única lógica del paquete es `EstrofasSync.ganadas(terminadas:)`,
la regla pura de las estrofas de «la espera enseña» (qué grupos de etapas de `HealthKitBridge.sync`
terminaron y trajeron filas, leídas de `SyncProgress.rowsByStage`); sin estado ni fecha, cubierta por
`swift test`, vive aquí y no en el acto para correr sin simulador.

**Consumidores.** Ayuda/Novedades (L2) iteran `Registro.por(pestana)`; los hitos (L3) y los tips
(L5/L7) son `Tip`s de TipKit cuyo `id` sale del registro (`Tips.configure([.displayFrequency(.daily)])`,
`MaxDisplayCount(3)` por defecto, los de primera sesión con `IgnoresDisplayFrequency(true)`);
los vacíos (L6) pintan `CenitDesign.LiquidVacio`, que recibe `Text` — el sistema de diseño no
importa el registro. Palanca DEBUG `-noop.tips <all|none|reset>` antes de `Tips.configure()`.

**Gate.** `Tools/check-ensenanza.py` (design-lint + `verify.sh quick`): todo archivo nuevo en
`Cenit/Screens/**` respecto a `Tools/ensenanza-baseline.txt` lleva `// ensenanza: <id>` con un id
grepeado de `FuncionalidadID.swift`; el baseline solo baja (job `baseline-monotony`). Los tests del
paquete leen `CHANGELOG.md` y `Localizable.xcstrings` vía `#filePath` (misma técnica que
`CatalogEntryArchivoExisteTests`): ids únicos, ≥1 pieza, `.novedad` con encabezado `## v`, claves
bajo `es`. Límite: el gate ve archivos, no sub-vistas dentro de uno existente.

---

## 11. Design principles, restated

1. **Offline by construction.** There is no network client anywhere in the data path. The SQLite file
   and the UI are the whole system. One narrow, user-controlled exception exists outside the data path —
   exercise media (FER-722) — off by default and documented in §10.
2. **Decoded-first durability.** Metrics are committed before raw is queued; the raw outbox is a
   prunable convenience, never the source of truth.
3. **Pure cores, thin shell.** `CenitStore`, `StrandAnalytics`, and `StrandImport` are platform-pure
   and testable in isolation; the app target is the only SwiftUI surface.
4. **Interoperability, not impersonation.** Cénit reads your Apple Health data and your exports for your
   own use. It is not a medical device.

---

## Attribution

See [`ATTRIBUTION.md`](../ATTRIBUTION.md) and [`NOTICE`](../NOTICE) for full third-party credits and
[`DISCLAIMER.md`](../DISCLAIMER.md) for the not-a-medical-device notice.
