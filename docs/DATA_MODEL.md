# The on-device database

Cénit keeps everything it knows in one SQLite file on the phone. There is no server, no account and
no sync: what the app computes, it computes from rows it wrote itself. This document is the
reference for that file — the tables that exist today, what each column holds, how rows get in and
out, and the migration ledger that produced the current shape.

It describes the schema **as the code builds it**, at migration `v43`. Every claim here is checkable
against `Packages/CenitStore/Sources/CenitStore/`.

> Cénit is not a medical device. Nothing stored here is intended for diagnosis or treatment.

---

## Conventions

Four conventions run through the whole schema. They are worth learning once.

**Instants are unix seconds.** Every column named `ts`, `startTs`, `endTs`, `createdTs`,
`updatedTs`, `computedAt`, `decidedAt` or `createdAt` is an integer count of seconds since the
epoch. There are no date or datetime column types anywhere.

**Days are text.** Columns named `day` (and `startDay`) hold `YYYY-MM-DD` and are compared
lexicographically, which for that format is the same as comparing dates. The key is minted in the
**device's local zone** and parsed back in **UTC** for chart positions. That asymmetry is
deliberate and is the single contract in `DayKey` (`Packages/StrandModels/Sources/StrandModels/DayKey.swift`):
`DayKey.local(_:)` writes, `DayKey.parseUTC(_:)` reads, and `DayKey.utc(_:)` is the exact inverse of
the reader. Mixing the two directions is what produces phantom rows and off-by-one-day charts.

**Rows are partitioned by origin, not by hardware.** Most tables carry a `deviceId`. It names the
*source* the row came from, never a piece of equipment. See [Source partitions](#source-partitions).

**Writes are idempotent by natural key.** Nearly every write is an upsert whose conflict target is
the table's primary key, so replaying an import or re-running a nightly recompute converges instead
of duplicating. Where the conflict rule is more subtle than "last writer wins", it is called out in
[Write semantics](#write-semantics).

---

## The store object

The persistence layer is the `CenitStore` package. Its manifest
(`Packages/CenitStore/Package.swift`) declares `.iOS(.v16)` and `.macOS(.v13)`, ships a single
static library product, and depends on `BiometricStreams`, `StrandModels`, `StrandTraining` and
[GRDB](https://github.com/groue/GRDB.swift) from `6.0.0`. Strict concurrency checking is on for both
the target and its tests. Two compressed JSON resources ride along inside the bundle; they exist
only to drive one migration and are described under [v33](#the-catalog-remap-v33).

`CenitStore` is an **actor**. Its public API is `async`, and the GRDB calls it makes are the
*synchronous* ones, wrapped in two non-async helpers (`syncRead`, `syncWrite`) precisely so Swift's
overload resolution picks the blocking variants. Those blocking calls then run on the actor's own
serial executor, which is not the main thread. The effect is that database work never lands on the
UI thread and writes are serialized per handle.

### Two connection backends

`CenitStore.Backend` chooses what GRDB opens:

| Backend | GRDB type | Used by |
| --- | --- | --- |
| `.queue` (default) | `DatabaseQueue` — one connection | The sampling handle, and every in-memory test |
| `.pool(maxReaders:)` | `DatabasePool` — WAL reader pool | The repository handle that serves the dashboard |

The distinction matters for one reason. A single connection serializes reads *behind* writes, so a
long import could stall a screen. The pool gives the bulk dashboard read its own WAL reader
connections, so it never queues behind an engine write on the same handle.

`CenitStore.inMemory()` always returns a queue-backed store — GRDB's pool has no in-memory mode.

### Connection setup

`prepareDatabase` runs on every connection the backend opens, including a pool's **read-only**
ones. Three of the pragmas below only make sense on a writer, so they are guarded by a
`db.configuration.readonly` check; opening a reader would otherwise throw and take every read down
with it.

| Pragma | Value | Writers only | Purpose |
| --- | --- | --- | --- |
| `auto_vacuum` | `INCREMENTAL` | yes | Freed pages become reclaimable without rewriting the file. Takes effect immediately on a fresh database; on an existing one it waits for a `VACUUM`. |
| `journal_mode` | `WAL` | yes | Readers and the writer proceed concurrently. |
| `synchronous` | `NORMAL` | yes | The durable pairing for WAL: only an OS crash or power loss can cost the last transaction. |
| `cache_size` | `-16000` | no | About 16 MB of page cache, sized for multi-thousand-row imports. |
| `mmap_size` | `268435456` | no | 256 MB of memory-mapped I/O. |
| `temp_store` | `MEMORY` | no | Temporary tables stay in RAM. |

The busy timeout is five seconds (`config.busyMode = .timeout(5)`), so two handles on the same file
wait for each other rather than failing.

### Version reporting

`CenitStoreInfo.schemaVersion` is **derived**, not a constant: it returns
`CenitStore.makeMigrator().migrations.count`. `CenitStoreInfo.latestMigration` returns the last
registered identifier. Both read straight from the migrator, so neither can drift from reality. A
hand-maintained constant previously did drift, by four versions.

### Maintenance and introspection

| Method | What it does |
| --- | --- |
| `checkpointWAL()` | `PRAGMA wal_checkpoint(TRUNCATE)` — folds the WAL into the main file so a file-level copy is complete on its own. Runs as a barrier write, outside any transaction. |
| `vacuum()` | Full `VACUUM`. Returns free pages to the OS and converts an existing file to incremental auto-vacuum. Heavy: callers run it once, gated, off the launch path. Also a barrier write. |
| `integrityCheck()` | `PRAGMA integrity_check`, surfaced in the app as an explicit "verify my data" action. True only for `ok`. |
| `sampleCounts()` | Row counts for the live sample tables — the on-device proof that samples actually persisted. |
| `pageCountForTest()` | `PRAGMA page_count`, so a test can prove a purge plus vacuum really shrank the file. |
| `tableNames()`, `primaryKeyColumns(_:)`, `columnNamesForTest(table:)`, `indexNamesForTest(table:)` | Schema introspection for tests. |
| `queryPlanForTest(_:arguments:)` | Returns `EXPLAIN QUERY PLAN` detail lines, so tests can assert a hot read reaches an index instead of scanning. |

`VACUUM` and `wal_checkpoint` both refuse to run inside a transaction, which is why they use
`barrierWriteWithoutTransaction` rather than the ordinary write path.

---

## Source partitions

`deviceId` is a **partition key over origins**. It has never identified hardware, and today no
hardware writes to the database at all.

Three partitions are in play. Their exact string values are declared once in
`Cenit/App/AppModel.swift` and assembled into a read request in `DashboardSnapshot.swift`; treat
those declarations as the source of truth rather than transcribing the literals.

| Partition | Holds |
| --- | --- |
| Historical | Rows written by earlier versions. The label is kept because it is already on disk, not because anything still writes under it. |
| Derived | Rows a computation produced rather than a source delivering them. Its label is the historical one plus a suffix, so the two sort and rewrite together. |
| Apple Health | Everything imported or synced from Apple Health. |

Migration `v36` relabelled the historical partition in place, and did it by sweeping the **live
schema** (`sqlite_master` plus `pragma table_info`) rather than a hand-written table list — a
forgotten table would have silently orphaned the user's rows. The derived partition follows its
parent automatically, because the sweep rewrites the *prefix* rather than matching whole values.

### The integer surrogate

The two high-volume sample tables do not store that label as text. Migration `v21` replaced it with
a small integer, resolved through `deviceIdMap`:

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT | **Primary key.** The partition label. |
| `intId` | INTEGER NOT NULL UNIQUE | The surrogate used by `hrSample` and `rrInterval`. |

`CenitStore.resolvedDeviceId(_:createIfMissing:)` translates at the API boundary and caches the
result in actor-isolated state, so no lock is needed and the map is read at most once per partition.
The two directions differ on purpose:

- **Reads** pass `createIfMissing: false`. An unknown label returns `nil`, and the read yields an
  empty array — exactly what a partition with no rows would have produced.
- **Writes** pass `createIfMissing: true` and can never get `nil` back. That is what keeps `insert`
  from throwing on an unmapped label, which in turn is what stops a caller from acknowledging data
  it failed to persist.

The mapping deliberately lives in its own table rather than being tied to any registry row: sample
rows exist for partitions that have no counterpart anywhere else, so a join would drop them.

---

## The live schema

Twenty-nine tables exist after `v43`. They divide into six domains.

### Sensor samples

Two tables were rebuilt by `v21` as `STRICT, WITHOUT ROWID`. Both properties are load-bearing.
`WITHOUT ROWID` makes the primary key *be* the table, which removes the second full copy of the key
that a rowid table's automatic index keeps on every row. `STRICT` makes a downgraded binary fail
loudly instead of writing text into the integer partition column.

#### `hrSample` — heart rate

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | INTEGER NOT NULL | Integer surrogate from `deviceIdMap`. In the key. |
| `ts` | INTEGER NOT NULL | In the key. |
| `bpm` | INTEGER NOT NULL | Instantaneous rate, beats per minute. |

**Primary key** `(deviceId, ts)`. Inserted with `ON CONFLICT DO NOTHING` through a cached statement,
so a replayed range costs nothing and adds nothing.

Reads come in two shapes. `hrSamples(deviceId:from:to:limit:)` returns raw rows.
`hrBuckets(deviceId:from:to:bucketSeconds:)` returns the mean bpm per fixed-width bucket, keyed by
the bucket's start, aggregated **in SQL** — a fully worn day is roughly 86 000 rows, and a chart
needs a few hundred. `latestHRSampleTs(deviceId:)` returns `MAX(ts)`, the data frontier.

#### `rrInterval` — beat-to-beat intervals

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | INTEGER NOT NULL | Surrogate. In the key. |
| `ts` | INTEGER NOT NULL | In the key. |
| `rrMs` | INTEGER NOT NULL | Interval in milliseconds. **In the key.** |

**Primary key** `(deviceId, ts, rrMs)`. The interval itself is in the key because several intervals
can legitimately share one timestamp. Reads order by `ts ASC, rrMs ASC`. This table is the input to
every HRV computation.

#### `strengthHrSample` — pulse during a strength session

| Column | Type | Notes |
| --- | --- | --- |
| `sessionId` | TEXT NOT NULL | In the key. |
| `ts` | INTEGER NOT NULL | In the key. |
| `bpm` | INTEGER NOT NULL | |

**Primary key** `(sessionId, ts)`, added in `v41`. Keying on the session rather than a partition
makes a retried flush a no-op instead of a duplicate. There is no foreign key: rows are pruned
explicitly when a session is discarded or deleted, so the parent never vanishes underneath a live
capture.

### Day-grain caches

Four tables share the same grain — one row per source per civil day — and the same access pattern:
a lexicographic range over `day`, oldest first.

#### `dailyMetric`

The widest table in the schema and the app's main read model. Twenty columns, grown across four
migrations.

| Column | Type | Added | Notes |
| --- | --- | --- | --- |
| `deviceId` | TEXT NOT NULL | v4 | In the key. |
| `day` | TEXT NOT NULL | v4 | In the key. |
| `totalSleepMin` | REAL | v4 | |
| `efficiency` | REAL | v4 | |
| `deepMin`, `remMin`, `lightMin` | REAL | v4 | Minutes per stage. |
| `disturbances` | INTEGER | v4 | |
| `restingHr` | INTEGER | v4 | |
| `avgHrv` | REAL | v4 | |
| `recovery` | REAL | v4 | |
| `strain` | REAL | v4 | |
| `exerciseCount` | INTEGER | v4 | |
| `spo2Pct` | REAL | v7 | |
| `skinTempDevC` | REAL | v7 | Deviation from baseline, in °C. |
| `respRateBpm` | REAL | v7 | |
| `steps` | INTEGER | v11 | |
| `activeKcalEst` | REAL | v11 | |
| `effortConfidence` | TEXT | v32 | Confidence tier for the day's effort score. |
| `restConfidence` | TEXT | v32 | Confidence tier for the day's rest score. |

**Primary key** `(deviceId, day)`. Every column except the key is nullable.

The two confidence columns hold a raw tier string, not an enum. The type that defines those tiers
lives in `StrandAnalytics`, which sits *above* this package in the dependency graph, so the store
keeps plain text and the layer above translates. They are persisted rather than derived because the
effort tier's inputs are the day's whole raw pulse stream; recomputing it for a year of history at
read time is not viable.

#### `appleDaily`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId`, `day` | TEXT NOT NULL | **Primary key.** |
| `steps` | INTEGER | |
| `activeKcal`, `basalKcal` | REAL | |
| `vo2max` | REAL | |
| `avgHr`, `maxHr`, `walkingHr` | INTEGER | |
| `weightKg` | REAL | |

Apple-Health-specific daily aggregates, kept separate from `dailyMetric` so a source's own numbers
stay distinguishable from the app's derived ones. `appleHealthCoverage(deviceId:)` reports the first
and last day present plus a per-metric day count — the basis of the app's honest "how much do I
actually have" answer.

#### `metricSeries`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId`, `day`, `key` | TEXT NOT NULL | **Primary key.** |
| `value` | REAL NOT NULL | |

Where the two tables above are wide — a typed column per metric — this one is tall. Any scalar
metric, whatever its origin, projects into a single row and reads back by name, so a metric explorer
can list and compare without knowing each source's schema.

Reads are served by `idx_metricSeries_device_key_day` on `(deviceId, key, day)`. The primary key
orders `day` before `key` and therefore cannot serve a per-metric range scan, which is exactly why
that index exists. The batched read (`metricSeries(deviceId:keys:from:to:)`) orders by `key, day` in
SQL to match the index and avoid a temporary B-tree, then restores the public `day, key` order in
memory — cheap next to letting SQLite sort a long series.

#### `journal`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId`, `day`, `question` | TEXT NOT NULL | **Primary key.** |
| `answeredYes` | INTEGER NOT NULL | |
| `notes` | TEXT | |

One row per prompt answered per day. The grain is what makes a journal answer usable as an
experiment's lever.

### Session records

#### `sleepSession`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT NOT NULL | In the key. |
| `startTs` | INTEGER NOT NULL | In the key. |
| `endTs` | INTEGER NOT NULL | |
| `efficiency` | REAL | |
| `restingHr` | INTEGER | |
| `avgHrv` | REAL | |
| `stagesJSON` | TEXT | Stage breakdown, stored opaquely. |

**Primary key** `(deviceId, startTs)`. The range read matches on **overlap**, not on start:
`startTs <= to AND endTs >= from`. Filtering on `startTs` alone would drop a night that began before
the window and ran into it, which is precisely the night a morning screen needs.

#### `workout`

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId`, `startTs`, `sport` | | **Primary key.** |
| `endTs` | INTEGER NOT NULL | |
| `source` | TEXT NOT NULL | Origin string, finer-grained than `deviceId`. |
| `durationS`, `energyKcal`, `strain`, `distanceM` | REAL | |
| `avgHr`, `maxHr` | INTEGER | |
| `zonesJSON`, `notes` | TEXT | |

`source` carries the writing app's name where one exists, so two imports of the same bout can be
told apart. It also carries the derived partition for computed bouts, which is why `v36` had to move
it in lockstep with `deviceId`.

### The strength domain

Fifteen tables, all user-authored, all keyed by UUID strings rather than by `(partition, time)`.
That difference is the point: this is relational data the user edits, not a sample stream. Array
fields are JSON text columns.

**Catalog and overrides.** The seed exercise catalog is a bundled resource in `StrandTraining`, not
rows in SQLite. Only what the user adds or changes persists here.

| Table | Key | Holds |
| --- | --- | --- |
| `customExercise` | `id` | User-created exercises: `name`, `type`, `equipment`, `primaryMuscles`, `secondaryMuscles`, `cues`, plus `bodyParts` and `gifUrl` from `v27`. |
| `exerciseTypeOverride` | `exerciseId` | A user's override of how an exercise is measured, including for a catalog entry. One row per exercise, so setting it is an upsert and reverting is a delete. |
| `learnedExerciseAlias` | `name` | A remembered mapping from a normalized imported name to an exercise id, so the next import of that name matches unaided. |

**Plans.** A routine is a folder-able ordered list of exercises, each of which owns an ordered list
of prescribed sets.

| Table | Key | Holds |
| --- | --- | --- |
| `routineFolder` | `id` | `name`, `sortOrder`. |
| `routine` | `id` | `name`, `tag`, `createdTs`, `updatedTs`, `sortOrder`, and `folderId` (`v18`, nullable — no folder). |
| `routineExercise` | `id` | `routineId`, `exerciseId`, `position`, the legacy `targetSets`/`targetReps`/`targetWeightKg`, `warmupPercents`, `restMode`, `restSeconds`; `supersetGroup` (`v15`, nullable — equal values within a routine form one superset); `hrRestReference`/`hrRestValue` (`v19`); the five progression columns (`v29`, `v30`, `v42`); and `note` (`v39`). |
| `routineSet` | `id` | `routineExerciseId`, `position`, `kind`, `reps`, `weightKg`; four nullable rest overrides (`v26`, null means inherit from the exercise); `repsRangeTop` (`v38`, null means a single fixed target); `mode` (`v42`). |
| `routineSchedule` | `weekday` | One routine per weekday, 1 through 7. The weekday *is* the key, so assigning a day is an idempotent upsert. At most seven rows, so no index. There is no foreign key: deleting a routine clears its schedule rows in the same transaction, and a dangling id derives to a rest day rather than crashing. |
| `program` | `id` | A singleton keyed `'active'`: `name`, `weeks`, `startTs`, `deloadRule`, `endMode`, `templateId`, `createdTs`. The current week is **derived** from `startTs` and the weeks actually trained, never stored — there is no column that can drift. |

**Performed work.**

| Table | Key | Holds |
| --- | --- | --- |
| `strengthSession` | `id` | `routineId`, `startTs`, `endTs`, `deviceId`, `strain`, `avgHr`, `notes`; `energyKcal`/`energySource` (`v26`, null means a session predating them — the UI shows nothing rather than inventing a number); and from `v42` `strainSource`, `sessionRpe`, `sessionRpeSource`, `trimpPerAU`, `source`, `title`, `programWeek`, `deload`. |
| `setEntry` | `id` | `sessionId`, `exerciseId`, `position`, `kind`, `weightKg`, `reps`, `timeS`, `distanceM`, `done`, `ts`; `rpe` (`v34`, nullable with no default — null means not captured, never zero); `restTakenS` (`v40`, the real rest that followed the set, pauses excluded); `mode` (`v42`). |
| `strengthExerciseNote` | `id` | `sessionId`, `exerciseId`, `setPosition`, `text`, `ts`. A separate table rather than a column, because a note is not tied to one set row and needs its own lifecycle. |
| `personalRecord` | `id` | The composite `"<exerciseId>:<metric>"`, plus `exerciseId`, `metric`, `valueKg`, `reps`, `ts`. |
| `progressionOptOut` | `(sessionId, exerciseId)` | Presence means the user reverted a raise for that session, so it counts as neither a hit nor a miss in the progression cycle. |
| `inProgressStrengthSession` | `id` | A singleton control row holding a JSON snapshot plus `updatedTs`. Written on start and on each durable edit, restored at launch, deleted on save or discard, so killing the app mid-workout does not lose it. |

### Diet

| Table | Key | Holds |
| --- | --- | --- |
| `dietPlan` | `id` | `deviceId`, and the denormalized `nombre`, `idioma`, `ciclo`, `createdAt`, alongside `payloadJSON`. The payload is **opaque** to the store: the nested meals and options are never parsed here, and the denormalized columns exist so a plan can be listed without decoding it. |
| `dietAdherence` | `(deviceId, day, mealId)` | `status` (tri-state), `note`, and `optionIndex` (`v16`, the zero-based index of which equivalent option was eaten; null means unrecorded). The option index is a record only — it does not move the adherence percentage. |

### Experiments and infrastructure

| Table | Key | Holds |
| --- | --- | --- |
| `experiment` | `id` | A single-subject experiment: the `behavior` lever, the `outcome` metric, `expectedSign`, `startDay`, `windowDays`, `status`, and the verdict columns `result`, `effectDelta`, `effectSize`, `pValue`, `nWith`, `nWithout`, `decidedAt`. Verdict columns fill only when a verdict is computed. The app runs one at a time; the table keeps the full history. |
| `deviceIdMap` | `deviceId` | The partition-label to integer-surrogate mapping described above. |
| `cursors` | `name` | A generic key to integer store. Accessors namespace their keys by prefix so two uses cannot collide. |

---

## Indexes

Eight indexes exist beyond the primary keys.

| Index | Table | Columns | Added |
| --- | --- | --- | --- |
| `idx_metricSeries_device_key_day` | `metricSeries` | `deviceId, key, day` | v9 |
| `idx_routineExercise_routine_pos` | `routineExercise` | `routineId, position` | v13 |
| `idx_setEntry_session_pos` | `setEntry` | `sessionId, position` | v13 |
| `idx_setEntry_exercise_ts` | `setEntry` | `exerciseId, ts` | v13 |
| `idx_personalRecord_exercise` | `personalRecord` | `exerciseId` | v13 |
| `idx_routineSet_re_pos` | `routineSet` | `routineExerciseId, position` | v17 |
| `idx_exNote_ex` | `strengthExerciseNote` | `exerciseId, ts` | v35 |
| `idx_exNote_sess` | `strengthExerciseNote` | `sessionId` | v35 |

The sample tables carry none: their primary key *is* their storage, and every read is a prefix of
it. `QueryPlanTests` asserts that the hot reads produce a `SEARCH … USING …` step rather than a
full scan, so an index that stops being used fails a test instead of quietly costing a scan.

---

## Migration ledger

Migrations are registered in `Database.swift` under `makeMigrator()` and run in order on every open.
Identifiers are contiguous `v1` through `v43`; a test pins that contiguity, which is what lets
`schemaVersion` simply count them.

| Version | Change |
| --- | --- |
| v1 | Initial tables: a device registry, four decoded sample streams, and a raw frame outbox. |
| v2 | `cursors`. |
| v3 | Four more sample streams (oximetry, skin temperature, respiration, gravity). |
| v4 | `sleepSession` and `dailyMetric`. |
| v5 | A per-row `synced` flag on all eight stream tables, for an upload path since removed. |
| v6 | A nullable charging flag on the battery stream. |
| v7 | `dailyMetric` gains `spo2Pct`, `skinTempDevC`, `respRateBpm`. |
| v8 | `journal`, `workout`, `appleDaily`. |
| v9 | `metricSeries` and its `(deviceId, key, day)` index. |
| v10 | A step-counter stream table. |
| v11 | `dailyMetric` gains `steps` and `activeKcalEst`. |
| v12 | `experiment`. |
| v13 | The strength tracker: `customExercise`, `routine`, `routineExercise`, `strengthSession`, `setEntry`, `personalRecord`, plus four indexes. |
| v14 | `dietPlan` and `dietAdherence`. |
| v15 | `routineExercise.supersetGroup`, nullable. |
| v16 | `dietAdherence.optionIndex`, nullable. |
| v17 | `routineSet` plus its index, back-filled by a recursive CTE that expands each existing exercise's `targetSets` into that many `work` rows carrying the single legacy reps and weight. Old routines therefore open one-to-one, and the legacy target columns stay as derived compatibility fields. |
| v18 | `routineFolder`, and a nullable `routine.folderId`. Deleting a folder nulls its routines rather than deleting them, so there is no cascade here. |
| v19 | `routineExercise.hrRestReference` and `hrRestValue`, defaulted so every existing routine keeps its prior behavior exactly. |
| v20 | Deletes every row of the oximetry stream — written but never read — while keeping the empty table so existing readers still compile. |
| v21 | Rebuilds the five 1 Hz sample tables as `STRICT, WITHOUT ROWID` with an integer partition surrogate, and creates `deviceIdMap`. See [the rebuild](#the-rebuild-v21). |
| v22 | `learnedExerciseAlias`. |
| v23 | `routineSchedule`. |
| v24 | `exerciseTypeOverride`. |
| v25 | A per-day body-clock phase table. |
| v26 | Four nullable rest columns on `routineSet`, back-filled by copying each parent exercise's rest onto all of its sets; plus `strengthSession.energyKcal` and `energySource`. An orphan set stays null and inherits at runtime rather than being lost. |
| v27 | `customExercise` gains `bodyParts` and `gifUrl`. The `cues` column is reused for the renamed instructions field: the field was renamed, the column was not, because shipped migrations are not edited. |
| v28 | `inProgressStrengthSession`. |
| v29 | Four progression columns on `routineExercise`, defaulted so a pre-existing routine reads back with progression off. |
| v30 | `routineExercise.progressionIgnoreRecovery`, default off. |
| v31 | `progressionOptOut`. |
| v32 | `dailyMetric.effortConfidence` and `restConfidence`. |
| v33 | The exercise-catalog remap. See [below](#the-catalog-remap-v33). |
| v34 | `setEntry.rpe`, nullable with no default. |
| v35 | `strengthExerciseNote` and its two indexes. |
| v36 | Relabels the source partition across the live schema. |
| v37 | Drops ten tables that no longer have a consumer. See [Removed schema](#removed-schema). |
| v38 | `routineSet.repsRangeTop`, nullable. |
| v39 | `routineExercise.note`, nullable and normalized to null rather than empty on write. |
| v40 | `setEntry.restTakenS`, nullable. |
| v41 | `strengthHrSample`. |
| v42 | One migration for five features at once — eight columns on `strengthSession`, `progressionUseRPE` on `routineExercise`, and `mode` on both `routineSet` and `setEntry`. Bundling them was deliberate: it kept three parallel branches from colliding on a migration number. |
| v43 | `program`. |

### Rules that govern every migration

**Append-only.** A shipped migration is never edited. A change is always a new `vN+1` plus a case in
`MigrationTests`. Editing one would leave installs that already ran it in a state no code path
describes.

**Every `ADD COLUMN` goes through `addColumnIfMissing`.** It checks the live schema first and does
nothing if the column is already there. Without it, a database that grew the column during local
iteration throws "duplicate column" on *every* launch, which wedges startup rather than failing
once. New-table creation uses `ifNotExists` for the same reason.

**Defaults are chosen so old rows keep their old behavior.** This is the recurring pattern: `v19`,
`v26`, `v29`, `v30` and `v38` all pick a default or a back-fill that reproduces the prior behavior
bit for bit, so upgrading changes nothing the user can see.

**Null means "absent", not zero.** `setEntry.rpe`, `strengthSession.energyKcal` and
`routineSet.repsRangeTop` are all nullable with no default, precisely so the UI can distinguish
"not captured" from a real value.

### The rebuild (v21)

`v21` is the only migration that rewrites existing tables, and it is worth reading as the template
for how to do that safely.

A rowid table with a composite primary key keeps a second copy of that key, plus the rowid, in an
automatic index on every row. For five tables holding tens of millions of 1 Hz samples, that copy
was most of the file. The rebuild makes the primary key the table itself and replaces the repeated
text partition label with a small integer.

The safety comes from three properties. The whole body runs inside GRDB's single migration
transaction, so a crash rolls back completely and retries clean. Each old table is dropped only
after its rebuilt copy passes a row-count assertion, **in the same commit**, so no half-state is
ever persisted. And a mismatch throws `MigrationError.rowCountMismatch`, which forces the rollback
rather than continuing.

### The catalog remap (v33)

The exercise catalog changed sources, and the ids changed with it. The user's history referenced
those ids across six tables, so a straight swap would have orphaned every logged set.

Two compressed maps ship inside the package. One maps an old id to its new slug. The other carries
the name, type, equipment and muscles for the old ids that have **no** counterpart in the new
catalog. The migration walks every id actually in use and does one of three things: rewrite the
reference if a new slug exists; materialize a `customExercise` carrying the old id if only the
legacy record exists; leave it alone otherwise.

Two details make it survivable. `UPDATE OR REPLACE` absorbs the rare case where two old ids collapse
onto one new slug, deduplicating rather than crashing on a key collision. And `personalRecord`'s
composite primary key is rebuilt alongside its `exerciseId`, since the id is derived from it. The
invariant afterwards is that every in-use exercise id resolves, to either a catalog entry or a
custom one. Re-running finds nothing left to remap, so it is idempotent. If the bundled resources
are missing, the migration is a no-op rather than a failure.

---

## Write semantics

Most upserts are plain: conflict on the primary key, overwrite the non-key columns. Three write
paths are not plain, and each deviation exists to prevent a specific class of data loss.

**Daily metrics never blank a filled column.** `upsertDailyMetrics` writes every column as
`COALESCE(excluded.X, X)`, so an incoming `nil` *preserves* what is already there while a real value
still overwrites. The nightly engine re-scores a whole window on each pass, and a night whose sleep
session is not yet detected comes back with nulls. Without the coalesce, that pass would wipe a
previously good day. Clearing a day is an explicit delete instead — no caller relies on a null
upsert to clear, and rows from different sources never share a key.

**Load is monotonic in the direction of real load.** `strain` is the one column that does not use
coalesce. Its rule is a three-branch case: a scored value always wins; an already-persisted positive
value is never regressed to zero or null by a later partial resync; and only "rest" and "missing"
may correct each other. That last branch matters, because it lets a false zero written from
incomplete data still be walked back to null when the day reclassifies as missing.

**Bulk writes are batched against SQLite's variable limit.** SQLite allows 999 bound variables per
statement. `upsertDailyMetrics` binds 20 per row and batches 49 rows (980 variables);
`upsertMetricSeries` binds 4 and batches 200 (800). A multi-year import flattens to tens of
thousands of points, and one statement per row meant a round trip each — minutes on a phone.

Sample inserts use cached statements and `ON CONFLICT DO NOTHING`, and return the number of rows
*actually* inserted, so a caller can tell new data from a replay.

---

## Read semantics

Two read shapes cover almost everything.

**Range reads** follow one template: filter the partition and a closed interval, order ascending,
limit. They exist for samples, sleep sessions, workouts, daily metrics, journal entries and metric
series.

**The dashboard snapshot** is the exception. `DashboardReadRequest` names the three partitions, a
day window, an instant window, a sleep limit and two source toggles; `dashboardSnapshot` returns
every series the main screen needs in a single pass — imported, computed and Apple-sourced days and
sleeps, the Apple aggregates, five metric series, strength session loads and workout spans. It runs
`nonisolated` on the pool's reader connections, which is the whole reason the repository handle is
a pool: the screen's read never waits behind an import write.

The row SQL and mapping for daily metrics, sleep sessions, Apple aggregates and metric series live
in shared fetch helpers, so the single-purpose accessor and the bulk snapshot cannot drift apart.

---

## Removed schema

Two migrations subtract, and what they left behind is worth knowing.

`v20` emptied the oximetry sample table. Its raw ADC values were written continuously and read
never — the figure the UI shows comes from a daily column — so they were a sixth of the file for
nothing. The table itself stayed so existing readers kept compiling.

`v37` dropped ten tables outright: the device registry, the event log, the battery series, the raw
frame outbox, the five decoded sample streams that no longer had a producer, and the body-clock
phase table. Each had zero live consumer. Everything else was untouched — this was subtraction, not
a rebuild — and `DROP TABLE IF EXISTS` makes it idempotent against any prior state.

Because `VACUUM` cannot run inside a migration transaction, neither of these reclaims disk on its
own. The one-time compaction runs after launch, gated, so the file actually shrinks rather than
merely freeing pages.

Three artifacts of these removals survive in the API on purpose:

- `upsertDevice(id:mac:name:)` is now an inert no-op with an unchanged signature, because a live
  caller still invokes it and writing to a dropped table would throw on every open.
- `sampleCounts()` still returns a six-field tuple, four of whose members are hardcoded zero,
  because a caller destructures that exact shape.
- The `synced` column added by `v5` was dropped from the tables `v21` rebuilt and is written by
  nothing anywhere. Treat it as gone.

> **Known inconsistency.** `Reads.swift` still exposes `skinTempSamples(...)` and
> `gravitySamples(...)`, which query tables `v37` dropped. They compile but would throw at runtime.
> They are not covered here as live API; removing them is tracked separately.

---

## Tests

`Packages/CenitStore/Tests/CenitStoreTests/` holds twenty-one test files. Three carry most of the
weight:

- **`MigrationTests`** — by far the largest. It exercises the ledger itself: contiguity of the
  version identifiers, the exact set of tables that must exist and must not exist after `v37` on
  both the upgrade and the fresh-install paths, the `v21` rebuild's row-count preservation, the
  `v36` relabel, and the back-fills. Several cases deliberately pin the migrator to an intermediate
  version, because a later migration drops the table under test.
- **`StrengthStoreTests`** — the relational domain's behavior, including personal-record recompute
  and the delete-and-restore round trip.
- **`QueryPlanTests`** — asserts the hot reads reach an index.

The rest cover one surface each: cursors, day keys, the dashboard snapshot, diet, experiments, the
in-progress session snapshot, inserts, the journal and workout caches, metric series, the metrics
cache, personal-record queries, programs, plain reads, both connection backends, and workout merge.

Every one of them runs against an in-memory store, so `swift test` in this package needs no
simulator, no HealthKit and no device.
