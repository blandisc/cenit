# Cénit — On-Device Data Model

Cénit is a standalone, fully offline health app on **Apple Health**. It stores HealthKit syncs,
file imports, and on-device computed metrics in a single local SQLite database. Older installs may
still carry dormant legacy partitions in the same DB, from a retired third-party wearable
integration. This document describes that on-device database: the tables, their natural keys,
indexes, and how the schema is installed.

> **Scope note.** Cénit is **not a medical device** — none of the stored values are intended for
> diagnosis or treatment.

---

## Where the database lives

The persistence layer is the `CenitStore` Swift package
(`Packages/CenitStore`), built on [GRDB](https://github.com/groue/GRDB.swift) over SQLite. Like
every package in the repo, it declares both platforms — `.iOS(.v16)` and `.macOS(.v13)`
(`Packages/CenitStore/Package.swift`) — and is UI-framework agnostic, so the same schema and
storage code back the `Cenit` app from a single cross-platform core.

The app target opens the database at a fixed, per-user location (`Cenit/Data/StorePaths.swift`):
`Application Support/Cenit/cenit.sqlite`, inside the app's sandbox. An install created before
FER-398 carries the previous folder and filename instead; a one-time migration at launch moves it
onto the `Cenit` names (see `docs/ARCHITECTURE.md` §2), so the legacy path is a transitional state,
never a second supported location. Tests use an in-memory database via `CenitStore.inMemory()`.

### Connection configuration

`CenitStore.init(path:backend:)` (`Packages/CenitStore/Sources/CenitStore/Store.swift`) opens either
a single `DatabaseQueue` (`.queue`, the default) or a WAL reader pool (`.pool(maxReaders:)`, what the
app's handle uses so the dashboard read never queues behind a long write), and applies these PRAGMAs
on **every** connection:

| PRAGMA | Value | Why |
| --- | --- | --- |
| `auto_vacuum` | `INCREMENTAL` | Freed pages stay reclaimable. Set before any table exists, or a fresh database ignores it. |
| `journal_mode` | `WAL` | Concurrent readers (pool) and the actor-serialized writer can read/write without deadlocking. |
| `synchronous` | `NORMAL` | Durable pairing with WAL — only an OS crash or power loss can lose the last transaction. |
| `cache_size` | `-16000` | ~16 MB page cache for multi-thousand-row import/backfill writes. |
| `mmap_size` | `268435456` | 256 MB memory-mapped I/O. |
| `temp_store` | `MEMORY` | In-memory temp tables. |
| `busyMode` | `.timeout(5)` | 5-second busy timeout under write contention. |

The first three are **write** PRAGMAs and run only when the connection is not read-only. In a pool the
same preparer also runs on reader connections, where they would throw — and a throwing reader takes
every dashboard read down with it.

`CenitStore` is an `actor`: all GRDB calls run on the actor's serial executor (off the main
thread) through the `syncRead` / `syncWrite` helpers. The one deliberate exception is
`dashboardSnapshot`, which is `nonisolated` and reads through the shared writer directly, so the whole
dashboard is one transaction and one WAL snapshot.

---

## Schema at a glance

29 user tables, in six groups:

| Group | Tables |
| --- | --- |
| **Partition map** | `deviceIdMap` |
| **Beat streams** (durable, high volume) | `hrSample`, `rrInterval` |
| **Bookkeeping** | `cursors` |
| **Metric caches** | `dailyMetric`, `sleepSession`, `journal`, `workout`, `appleDaily`, `metricSeries` |
| **Experiments and diet** | `experiment`, `dietPlan`, `dietAdherence` |
| **Strength tracker** | `customExercise`, `learnedExerciseAlias`, `exerciseTypeOverride`, `routineFolder`, `routine`, `routineExercise`, `routineSet`, `routineSchedule`, `program`, `strengthSession`, `setEntry`, `personalRecord`, `progressionOptOut`, `strengthExerciseNote`, `strengthHrSample`, `inProgressStrengthSession` |

All timestamp columns named `ts`, `startTs`, `endTs`, `createdTs`, etc. are **unix seconds**
(integers). Day-keyed tables use a `day` text column in `YYYY-MM-DD` form (the device's local civil
day) and compare it lexicographically.

The **byte-exact** source of truth for the schema is
`Packages/CenitStore/Tests/CenitStoreTests/Resources/legacy-schema.sql`: a verbatim `sqlite3 .schema`
dump of a real migrated database. A test compares `sqlite_master` of a fresh install against it
character by character, so a lost `STRICT`, a dropped `NOT NULL` or a changed `DEFAULT` fails the
build rather than surfacing months later as a null where the code expected a value.

---

## How the schema is installed

`Packages/CenitStore/Sources/CenitStore/Schema.swift` registers **one** migration, `"v43"`, whose
body is the whole DDL.

The identifier is load-bearing. A database installed before FER-393 carries the 43 identifiers
`v1`…`v43` of the previous incremental history in its `grdb_migrations` ledger, and GRDB silently
ignores applied identifiers a migrator doesn't know about. Registering only `"v43"` means that
database reads it as already applied, finds nothing pending, and **executes not one schema
statement**. A fresh install arrives with an empty ledger, runs `"v43"`, and gets the full schema.

Two rules follow, and both are enforced by tests:

- **The next migration is `"v44"`.** Never reuse `"v1"`…`"v42"`: an installed database already has
  them in its ledger and would skip them in silence, leaving its schema behind with no visible error.
- **`eraseDatabaseOnSchemaChange` stays off.** With it on, GRDB sees 43 applied identifiers it does
  not recognize, concludes the schema changed, and erases the file.

Every future `ADD COLUMN` goes through `CenitStore.addColumnIfMissing`, which checks the live schema
first: iterating a migration locally and reinstalling over the same on-device database must be a
no-op, not a "duplicate column" throw that wedges startup.

---

## The partition key

`deviceId` is not hardware — it is the **per-source partition key**. The live values are
`"apple-health"` (imported from Apple Health, the live source), `"apple-health-noop"` (nightly
scalars computed on top of it), `"strap"` (imported history from the band era, no live writer),
`"strap-noop"` (derived from it) and `"noop-journal"` (journal answers logged in Cénit rather than
imported). No public read crosses a partition and no public delete touches more than one.

### `deviceIdMap`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | **Primary key.** The partition label. |
| `intId` | INTEGER NOT NULL UNIQUE | Its integer surrogate. |

`hrSample` and `rrInterval` store the surrogate, not the label: a day of pulse at 1 Hz is ~86 000
rows, and a composite TEXT key kept a second copy of the same repeated string on every one of them.
The label lives here exactly once. The public API still takes and returns `deviceId: String` — the
actor translates at the boundary through a cache it owns, so no caller ever sees the integer. Reading
an unknown partition returns empty rather than throwing; writing one creates its mapping on demand,
so a write can never fail for a missing surrogate.

---

## Beat streams

Written by `CenitStore.insert(_:deviceId:)`, which persists **only** heart rate and R-R intervals.
`Streams` still carries skin-temperature, respiration and accelerometer arrays for dormant engines;
their tables no longer exist, so writing them would throw «no such table» and take the whole
transaction — including the beats that do live — down with it.

Both tables are `STRICT, WITHOUT ROWID`: the natural key *is* the table, with no `sqlite_autoindex`
copy of the key on every row. Inserts are idempotent (`ON CONFLICT DO NOTHING`) and `insert` returns
the rows *actually* written, so replaying an overlapping import returns 0 and changes nothing.

### `hrSample` — heart rate

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | INTEGER NOT NULL | The partition surrogate. Part of PK. |
| `ts` | INTEGER NOT NULL | Wall-clock unix seconds. Part of PK. |
| `bpm` | INTEGER NOT NULL | Beats per minute. |

**Primary key:** `(deviceId, ts)`. `latestHRSampleTs(deviceId:)` returns `MAX(ts)` here — the proof
that the source is still delivering. `hrBuckets` averages by time bucket **in SQL**; a day of samples
is not something to average in memory.

### `rrInterval` — R-R intervals (HRV source)

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | INTEGER NOT NULL | The partition surrogate. Part of PK. |
| `ts` | INTEGER NOT NULL | Wall-clock unix seconds. Part of PK. |
| `rrMs` | INTEGER NOT NULL | Beat-to-beat interval, milliseconds. Part of PK. |

**Primary key:** `(deviceId, ts, rrMs)` — several intervals can share one timestamp. Reads order by
`ts ASC, rrMs ASC` so a read is reproducible.

> Neither table has the `synced` column of the retired server-upload feature: it was dropped when they
> were rebuilt, and nothing recreates it.

---

## Bookkeeping

### `cursors`

A key/value table for one-shot flags and incremental-processing watermarks.

| Column | Type | Notes |
| --- | --- | --- |
| `name` | TEXT | **Primary key.** |
| `value` | INTEGER | Stored value (typically a timestamp or a `1` flag). |

Helpers namespace the `name`: `highwater:<stream>` (forward-only upload mark) and `read:<stream>`
(pull cursor). The distinct prefixes are contract — they keep the two marks of one stream from
colliding.

---

## Metric caches

These hold **derived metrics and imported aggregates**, not raw measurements. The name is a little
misleading: there is no invalidation, no dirty flag and no notification. They are durable rows of
already-computed values, rewritten by whoever recomputes them.

### `sleepSession`

One row per sleep session.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `startTs` | INTEGER NOT NULL | Session start, unix seconds. Part of PK. |
| `endTs` | INTEGER NOT NULL | Session end, unix seconds. |
| `efficiency` | DOUBLE | Sleep efficiency, nullable. |
| `restingHr` | INTEGER | Resting HR, nullable. |
| `avgHrv` | DOUBLE | Average HRV, nullable. |
| `stagesJSON` | TEXT | Verbatim JSON array of stage segments (`[{start,end,stage}]`), nullable — a string so the cache stays schema-agnostic about staging shape. |

**Primary key:** `(deviceId, startTs)`; a conflict replaces every other column. Reads return the
sessions that **overlap** the window (`startTs <= to AND endTs >= from`), not the ones that start
inside it: falling asleep before local midnight puts the night's start outside the window, and it is
still that night.

### `dailyMetric`

One row per local civil day — the central per-day rollup behind the dashboard. All metric columns are
nullable: `totalSleepMin`, `efficiency`, `deepMin`, `remMin`, `lightMin`, `disturbances`, `restingHr`,
`avgHrv`, `recovery`, `strain`, `exerciseCount`, `spo2Pct`, `skinTempDevC`, `respRateBpm`, `steps`,
`activeKcalEst`, `effortConfidence`, `restConfidence`.

**Primary key:** `(deviceId, day)`. Read by lexicographic `day` range, oldest first.

**The conflict rule is not a replacement** — it is the most delicate thing in the package. The engine
re-scores every night in its window on each pass, and a night whose sleep session isn't detected yet
comes back all nulls. So each column merges as `COALESCE(incoming, stored)`: the incoming value wins
when it carries something, the stored one survives when it doesn't. To **clear** a day you delete it
(`deleteDailyMetrics`), you never write nulls over it.

`strain` has its own, narrower rule, because a plain `COALESCE` gets one case wrong:

| stored | incoming | result | why |
| --- | --- | --- | --- |
| anything | `> 0` | **incoming** | a scored workout always wins |
| `> 0` | `0` | **stored** | a persisted load does not degrade to rest |
| `> 0` | `NULL` | **stored** | nor to «no data» |
| `NULL` | `0` | `0` | |
| `NULL` | `NULL` | `NULL` | |
| `0` | `NULL` | **`NULL`** | a stored 0 is usually a false rest from a pass without pulse; going back to «no data» is the honest answer |
| `0` | `0` | `0` | |

### `journal`

One answered daily prompt.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `day` | TEXT NOT NULL | `YYYY-MM-DD`. Part of PK. |
| `question` | TEXT NOT NULL | Prompt text. Part of PK. |
| `answeredYes` | INTEGER NOT NULL | `0`/`1`, mapped to/from `Bool`. |
| `notes` | TEXT | Free-text note, nullable. |

**Primary key:** `(deviceId, day, question)`. Read by `day` range, ordered `day ASC, question ASC`.
Deleting one answer is scoped to its partition, so clearing a natively-logged answer can never take
an identical imported row with it.

### `workout`

One workout. All metric columns nullable: `durationS`, `energyKcal`, `avgHr`, `maxHr`, `strain`,
`distanceM`, `zonesJSON`, `notes`; `endTs`, `sport` and `source` are `NOT NULL`.

**Primary key:** `(deviceId, startTs, sport)` — two sports starting at the same instant are two rows;
the same triple in three partitions is three. Read by `startTs` range (filtered by **start**, not
overlap), oldest first. `deleteWorkouts(deviceId:sport:from:to:)` sweeps a span of one sport, which is
what makes re-deriving detected workouts idempotent.

### `appleDaily`

Apple-Health daily aggregates. All metric columns nullable: `steps`, `activeKcal`, `basalKcal`,
`vo2max`, `avgHr`, `maxHr`, `walkingHr`, `weightKg`.

**Primary key:** `(deviceId, day)`; a conflict replaces every metric column. Read by lexicographic
`day` range, oldest first.

`appleHealthCoverage(deviceId:)` reports what the import managed to bring: the first and last day over
the **deduplicated union** of `appleDaily` and `dailyMetric` days, plus a per-metric day count under
ten fixed keys (`steps`, `active_kcal`, `vo2max`, `avg_hr` from `appleDaily`; `asleep_min`, `hrv`,
`resting_hr`, `spo2`, `resp_rate`, `skin_temp` from `dailyMetric`). A metric with zero days is
**absent** from the dictionary, never `0` — the UI draws «missing» from the missing key.

### `metricSeries`

A generic **long-format / EAV** metric store. Where the tables above are wide (a column per metric),
this is the tall counterpart: one row per `(deviceId, day, key)` with a single REAL `value`. Any
scalar, from any source, can be projected here and read back by key without a schema change.

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | Part of PK. |
| `day` | TEXT NOT NULL | `YYYY-MM-DD`. Part of PK. |
| `key` | TEXT NOT NULL | Metric identifier (e.g. `steps_est`, `hrv_lf`, `apple_rmssd_night`). Part of PK. |
| `value` | DOUBLE NOT NULL | The scalar value. |

**Primary key:** `(deviceId, day, key)`; a conflict takes the incoming value.

**Index** — `idx_metricSeries_device_key_day` on `(deviceId, key, day)`. The primary key orders `day`
before `key`, so it cannot serve a per-metric range read. The multi-key read orders **in SQL by
`(key, day)`** to follow this index — asking SQLite for `(day, key)` would build a temp B-tree over
thousands of rows — and restores the public `(day, key)` order in memory.

---

## Strength tracker

Relational, UUID-string PKs; array fields (muscles, cues, warm-up percents) are JSON text columns.
`routine` → `routineExercise` → `routineSet` is the plan; `strengthSession` → `setEntry` is the log;
`personalRecord` is derived at save. `strengthHrSample` holds the watch pulse captured during a live
session (`(sessionId, ts)`), `strengthExerciseNote` the per-session notes, `progressionOptOut` the
sessions the progression must treat as neither hit nor miss, and `inProgressStrengthSession` a single
JSON snapshot so a crash mid-workout doesn't lose it. `program` is a singleton (PK `id = 'active'`).

Column-level detail lives with the code in `StrengthStore.swift` and, exactly, in
`legacy-schema.sql`.

---

## Index summary

| Index | Table | Columns |
| --- | --- | --- |
| *(implicit PK)* | every table | (its natural key) |
| `idx_metricSeries_device_key_day` | `metricSeries` | `deviceId, key, day` |
| `idx_routineExercise_routine_pos` | `routineExercise` | `routineId, position` |
| `idx_routineSet_re_pos` | `routineSet` | `routineExerciseId, position` |
| `idx_setEntry_session_pos` | `setEntry` | `sessionId, position` |
| `idx_setEntry_exercise_ts` | `setEntry` | `exerciseId, ts` |
| `idx_personalRecord_exercise` | `personalRecord` | `exerciseId` |
| `idx_exNote_ex` | `strengthExerciseNote` | `exerciseId, ts` |
| `idx_exNote_sess` | `strengthExerciseNote` | `sessionId` |

Every other read is served by a primary key. `QueryPlanTests` pins this: each hot read must reach its
table through `SEARCH … USING …`, never a bare full-table scan.

---

## Provenance

Persistence is `CenitStore`; the local recovery / strain / HRV / sleep math is `StrandAnalytics`;
and the Apple Health importers are `StrandImport`.

> **Reminder.** Cénit is not a medical device. All stored data is the user's own, kept entirely on
> the user's device.
