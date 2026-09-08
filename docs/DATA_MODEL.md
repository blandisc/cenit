# The on-device database

Cénit keeps everything it knows in one SQLite file on the phone. There is no server, no account and
no sync: what the app computes, it computes from rows it wrote itself. This document is the reference
for that file — the tables that exist, what each column holds, how rows get in and out, and how the
schema is installed.

Every claim here is checkable against `Packages/CenitStore/Sources/CenitStore/`.

> Cénit is not a medical device. Nothing stored here is intended for diagnosis or treatment.

---

## Conventions

Four conventions run through the whole schema. They are worth learning once.

**Instants are unix seconds.** Every column named `ts`, `startTs`, `endTs`, `createdTs`, `updatedTs`,
`decidedAt` or `createdAt` is an integer count of seconds since the epoch. There are no date or
datetime column types anywhere.

**Days are text.** Columns named `day` (and `startDay`) hold `YYYY-MM-DD` and compare
lexicographically, which for that format is the same as comparing dates. The key is minted in the
**device's local zone** and parsed back in **UTC** for chart positions. That asymmetry is deliberate
and is the single contract in `DayKey` (`Packages/StrandModels/Sources/StrandModels/DayKey.swift`).
Mixing the two directions is what produces phantom rows and off-by-one-day charts.

**Rows are partitioned by origin, not by hardware.** Most tables carry a `deviceId`. It names the
*source* a row came from, never a piece of equipment.

**Writes are idempotent by natural key.** Nearly every write is an upsert whose conflict target is
the table's primary key, so replaying an import or re-running a nightly recompute converges instead
of duplicating. Where the conflict rule is subtler than "last writer wins", it is called out under
[Write semantics](#write-semantics).

---

## The store object

The persistence layer is the `CenitStore` package. Its manifest declares `.iOS(.v16)` and
`.macOS(.v13)`, ships a single static library, and depends on `BiometricStreams`, `StrandModels`,
`StrandTraining` and [GRDB](https://github.com/groue/GRDB.swift).

`CenitStore` is an **actor** (`Store.swift`). Its public API is `async`, and the GRDB calls it makes
are the *synchronous* ones, wrapped in helpers that are deliberately **not** `async`: GRDB marks its
synchronous variants as a disfavoured overload, so an `async` wrapper would silently select the
asynchronous one and change behavior under the caller. Those blocking calls then run on the actor's
own serial executor, off the main thread.

### Two connection backends

| Backend | GRDB type | Used by |
| --- | --- | --- |
| `.queue` (default) | `DatabaseQueue`, one connection | The sampling handle, and every in-memory test |
| `.pool(maxReaders:)` | `DatabasePool`, a WAL reader pool | The app handle that serves the dashboard |

A single connection serializes reads *behind* writes, so a long nightly pass could stall a screen.
The pool gives the bulk dashboard read its own reader connections. `inMemory()` is always
queue-backed, because GRDB's pool has no in-memory mode.

Opening **runs the migration before returning**. If it throws, the initializer throws: a half-migrated
database is never handed out.

### Connection setup

`prepareDatabase` runs on every connection, including a pool's **read-only** ones. Three pragmas only
work on a writer, so they sit behind a `readonly` guard; without it, opening a reader fails and takes
the whole dashboard read down, a failure mode the queue never shows.

| Pragma | Value | Writers only | Purpose |
| --- | --- | --- | --- |
| `auto_vacuum` | `INCREMENTAL` | yes | Freed pages stay reclaimable. **Order matters**: it only takes effect on a database with no tables yet, so it runs first. |
| `journal_mode` | `WAL` | yes | Readers and the writer proceed concurrently. |
| `synchronous` | `NORMAL` | yes | The durable pairing for WAL: only an OS crash or power loss can cost the last transaction. |
| `cache_size` | `-16000` | no | About 16 MB of page cache. |
| `mmap_size` | `268435456` | no | 256 MB of memory-mapped I/O. |
| `temp_store` | `MEMORY` | no | Temporary tables stay in RAM. |

The busy timeout is five seconds, so two handles on the same file wait for each other rather than
failing.

### Version reporting

`CenitStoreInfo.schemaVersion` counts the migrations the package registers, and `latestMigration`
returns the last identifier. Both are **derived from the migrator**, never written by hand: a loose
constant drifts the moment someone adds a migration and forgets to bump it. Today the count is one.

### Maintenance and introspection

| Method | What it does |
| --- | --- |
| `checkpointWAL()` | Folds the WAL into the main file and truncates it, so a file copy is complete on its own. Throws on a hard SQLite error, so the caller can fall back to a plain copy rather than save an incomplete backup. |
| `vacuum()` | Rewrites the file compactly, and is the only way a database created before incremental mode adopts it. |
| `pageCountForTest()` | Proves a purge plus vacuum actually shrank the file. |
| `tableNames()`, `primaryKeyColumns(_:)`, `columnNamesForTest(table:)`, `indexNamesForTest(table:)` | Schema introspection for tests. |
| `queryPlanForTest(_:arguments:)` | `EXPLAIN QUERY PLAN` detail lines, so a test can assert a hot read reaches an index. |

Both maintenance operations run **outside a transaction and behind a barrier**, with no readers alive
even on a pool. Neither can run inside one.

---

## Source partitions

`deviceId` is a **partition key over origins**. It has never identified hardware, and today no
hardware writes to the database at all. The exact string values are declared in the app layer; treat
those declarations as the source of truth rather than transcribing them.

### The integer surrogate

The two high-volume tables do not store the partition as text. They store a small integer, resolved
through `deviceIdMap`:

| Column | Type | Notes |
| --- | --- | --- |
| `deviceId` | TEXT | **Primary key.** The partition label. |
| `intId` | INTEGER NOT NULL UNIQUE | The surrogate used by `hrSample` and `rrInterval`. |

Without it, a composite key would repeat the same text on every one of millions of 1 Hz rows.

`partitionId(_:creating:)` translates at the boundary and caches the result in actor-isolated state,
so no lock is needed. The two directions differ on purpose:

- **Reads** pass `creating: false`. An unknown label returns nothing and the read yields an empty
  result. Asking about a source that does not exist yet is not an error.
- **Writes** pass `creating: true`, assign the next free integer, and can never return nothing, so no
  write can fail for a missing mapping.

The assignment inserts with `ON CONFLICT DO NOTHING` and then **re-reads inside the same
transaction**: if another writer won the race, its integer is the one to use.

---

## How the schema is installed

This is the part most likely to surprise someone who knew the previous shape.

**There is exactly one migration.** It is registered under the identifier `"v43"`, and it installs
the entire schema by executing the `CREATE` statements in order. The migrator is deliberately boring,
because the phone's file is the only copy of the user's data that exists.

The identifier is not arbitrary. A database already on a phone carries `v1` through `v43` in its
`grdb_migrations` ledger from the previous incremental history, and GRDB silently ignores ledger
entries a migrator does not know. Registering only `"v43"` means such a database reads it as already
applied, finds nothing pending, and **executes not one schema statement**. A fresh install arrives
with an empty ledger, runs it, and gets the complete schema. Both paths converge.

**The next migration is `"v44"`.** Never reuse `v1` through `v42`: an existing database already has
them in its ledger and would skip them in silence, leaving its schema behind with no visible error.

Two details make this safe to re-run.

**The DDL is pasted verbatim** from a reference dump, quotes and line breaks included. That makes the
shape test an exact string comparison against `sqlite_master`, able to catch a missing `STRICT`, a
forgotten `WITHOUT ROWID`, or a `DEFAULT` whose value changed.

**The existence guard lives in Swift, not in the SQL text.** Each object is created only if
`sqlite_master` does not already list it. Putting `IF NOT EXISTS` into the text would work, but
`sqlite_master` stores the *literal* statement that was executed, and editing the text to add a
clause would break the exact comparison precisely where it matters most. With the guard in Swift the
text stays intact and an unexpected run stays a no-op rather than an exception that would stop the
database from opening.

`addColumnIfMissing` survives for future migrations that widen a table. Every one of them goes
through it: a migration gets iterated several times during development and reinstalled over the same
phone database, and without the guard the second attempt hits "duplicate column" and leaves the app
unable to open its data.

`grdb_migrations` is not in the object list. GRDB creates it itself, idempotently.

---

## The tables

Twenty-nine tables and eight indexes. There are **no foreign keys** between them, so the install
order matters only for reading.

### Beats

Two tables, both `STRICT, WITHOUT ROWID` with the integer partition surrogate. Both properties are
load-bearing. `WITHOUT ROWID` makes the primary key *be* the table, which removes the second full copy
of the key that a rowid table's automatic index keeps on every row. `STRICT` makes a downgraded binary
fail loudly instead of writing text into the integer column.

| Table | Key | Columns |
| --- | --- | --- |
| `hrSample` | `(deviceId, ts)` | `bpm` |
| `rrInterval` | `(deviceId, ts, rrMs)` | The interval is in the key, because several can share one timestamp. |

A fully worn day is roughly 86 000 pulse rows, which is why these two are partitioned by integer and
the rest by text. Inserts use a cached statement with `ON CONFLICT DO NOTHING` and return how many
rows actually landed, so re-importing a period returns zero and leaves the file unchanged.

Only these two streams are persisted. The other fields the in-memory batch still carries belong to
tables that no longer exist; writing them would throw and take down the whole transaction, including
the beats that do live.

Reads come in two shapes: raw rows, and `HRBucket`, the mean pulse per fixed-width bucket aggregated
**in SQL**, because a chart needs a few hundred points rather than 86 000.

`strengthHrSample` is a third pulse table, keyed `(sessionId, ts)` rather than by partition, so a
retried flush during a live session is a no-op instead of a duplicate.

### Day-grain caches

Four tables share one grain, one row per source per civil day, and one access pattern, a
lexicographic range over `day`.

The name "cache" is misleading, and the source says so: there is no invalidation, no dirty flag and
no eviction. These are durable values the app rewrites when it recomputes.

**`dailyMetric`** is the widest table and the app's main read model: twenty columns covering the
scores, the sleep breakdown, the nightly vitals, steps, an energy estimate, and a confidence tier for
each of the two scores. Everything but the key is nullable. The two confidence columns hold a raw
tier string rather than an enum, because the type that defines those tiers lives in `StrandAnalytics`,
which sits *above* this package.

**`appleDaily`** holds the source's own daily aggregates, kept apart from the derived ones so a
source's numbers stay distinguishable from the app's.

**`metricSeries`** is the tall counterpart to those wide tables: any scalar from any source fits as a
day, a key and a value, read back by key, without inventing a column or a migration per new metric.
Its index on `(deviceId, key, day)` exists because the primary key orders `day` before `key` and so
cannot serve a per-metric range scan.

**`journal`** holds one answered prompt per day.

### Sessions

**`sleepSession`**, keyed `(deviceId, startTs)`, carries efficiency, resting pulse, average
variability and the stage breakdown as an opaque JSON string. Its range read matches on **overlap**,
not on start: someone who fell asleep before local midnight has a night that began outside the window
and that the window still has to return.

**`workout`**, keyed `(deviceId, startTs, sport)`, carries duration, energy, pulse, load, distance,
zone breakdown and notes. Its `source` column is finer-grained than `deviceId`, carrying the writing
app's name where one exists.

### The strength domain

Fifteen tables, all user-authored, all keyed by UUID strings rather than by partition and time. That
difference is the point: this is relational data the user edits, not a sample stream. Array fields are
JSON text columns, and the seed exercise catalog is a bundled resource in `StrandTraining`, not rows
here.

| Table | Key | Holds |
| --- | --- | --- |
| `customExercise` | `id` | User-created exercises, including coarse body parts and an optional media URL. |
| `exerciseTypeOverride` | `exerciseId` | A user's override of how an exercise is measured, including for a catalog entry. Setting it is an upsert; reverting is a delete. |
| `learnedExerciseAlias` | `name` | A remembered mapping from a normalized imported name to an exercise id. |
| `routineFolder` | `id` | Name and sort order. |
| `routine` | `id` | Name, tag, timestamps, sort order, and a nullable folder. |
| `routineExercise` | `id` | Position within a routine, legacy per-exercise targets, warm-up percentages, rest configuration, superset group, and the six progression columns. |
| `routineSet` | `id` | The per-set prescription, plus four nullable rest overrides that inherit from the exercise when null, a rep-range top, and a set mode. |
| `routineSchedule` | `weekday` | One routine per weekday. The weekday *is* the key, so assigning a day is an idempotent upsert. At most seven rows, so no index. |
| `program` | `id` | A singleton. The current week is **derived** from the start and the weeks actually trained, never stored, so no column can drift. |
| `strengthSession` | `id` | The performed session: times, load and its origin, session effort and its origin, energy and its origin, import provenance, program week and light-week flag. |
| `setEntry` | `id` | One performed set: load, reps, time, distance, done flag, effort rating, the real rest that followed, and a mode. |
| `strengthExerciseNote` | `id` | A note per exercise, optionally per set. A table rather than a column, because a note is not tied to one set row. |
| `personalRecord` | `id` | The composite of exercise and metric. |
| `progressionOptOut` | `(sessionId, exerciseId)` | Presence means a reverted raise, counting as neither a hit nor a miss. |
| `inProgressStrengthSession` | `id` | A singleton JSON snapshot, so killing the app mid-workout does not lose it. |

### Diet, experiments and bookkeeping

| Table | Key | Holds |
| --- | --- | --- |
| `dietPlan` | `id` | Denormalized name, language and cycle so a plan lists without decoding, plus the payload. The payload is **opaque** to the store: the nested meals are never parsed here. |
| `dietAdherence` | `(deviceId, day, mealId)` | A tri-state status, a note, and which equivalent option was eaten. The option index is a record only and does not move the adherence figure. |
| `experiment` | `id` | A single-subject experiment and its verdict columns, filled only when a verdict is computed. |
| `cursors` | `name` | Named marks: how far a process got, and what has already been done once. The smallest table and the most stubborn, since a misread flag makes a one-time compaction repeat on every launch or never run. Accessors namespace keys by prefix, and the prefixes are contract. |

---

## Indexes

| Index | Table | Columns |
| --- | --- | --- |
| `idx_metricSeries_device_key_day` | `metricSeries` | `deviceId, key, day` |
| `idx_routineExercise_routine_pos` | `routineExercise` | `routineId, position` |
| `idx_routineSet_re_pos` | `routineSet` | `routineExerciseId, position` |
| `idx_setEntry_session_pos` | `setEntry` | `sessionId, position` |
| `idx_setEntry_exercise_ts` | `setEntry` | `exerciseId, ts` |
| `idx_personalRecord_exercise` | `personalRecord` | `exerciseId` |
| `idx_exNote_ex` | `strengthExerciseNote` | `exerciseId, ts` |
| `idx_exNote_sess` | `strengthExerciseNote` | `sessionId` |

The beat tables carry none: their primary key *is* their storage, and every read is a prefix of it.
`QueryPlanTests` asserts the hot reads produce a search step rather than a full scan, so an index that
stops being used fails a test instead of quietly costing a scan.

---

## Write semantics

Most upserts are plain. Three things are not, and each exists to prevent a specific loss.

### Daily metrics never blank a filled column

The conflict rule is **not** a replacement. The engine re-scores every night in its window on each
pass, and a night whose sleep session is not yet detected comes back with nulls. If a null overwrote
what was stored, one partial pass would blank a whole day of history. So every column merges as
`COALESCE(incoming, existing)`: the incoming value wins when it has one, and the stored value survives
when it does not. To **delete** a day, delete it; do not write nulls over it.

### Load has its own, narrower rule

`strain` does not use that merge. Three cases, in order:

```
incoming > 0   → incoming    (a scored workout always wins)
existing > 0   → existing    (a persisted load is never degraded)
otherwise      → incoming
```

A persisted load is never walked back to "rest" (zero) or "missing" (null), because erasing it should
require deleting the day. But a stored zero, which is almost always a false rest from a pass with no
pulse, *can* return to null, which is the honest truth.

### Bulk writes work around two SQLite limits

`RowBatch` exists because an Apple Health import flattens years into tens of thousands of rows, and
one statement per row takes minutes and blocks the actor while a multi-row insert takes seconds.

The first limit is 999 bound variables per statement, so the chunk size is that divided by the columns
per row.

The second is subtler and bites: **a single upsert statement cannot resolve the same conflict key
twice.** Two utilities handle it, and which one applies depends on the conflict rule.

- Where the rule **replaces** the row, `lastPerKey` keeps the last appearance of each key in the order
  of the first. That is "row by row, last wins" translated into one statement, resolved in memory
  beforehand with the same result.
- Where the rule **merges column by column**, keeping only the last appearance would lose values that
  only the first carried. So `passes` splits the rows into runs in which no key repeats: first
  appearances in pass one, second appearances in pass two, and so on. Applied in order, the passes
  reproduce row-by-row semantics exactly.

---

## Read semantics

**Range reads** follow one template: filter the partition and a closed interval, order ascending,
limit.

**The dashboard snapshot** is the exception. It returns every series the main screen needs in a single
pass, and runs `nonisolated` on the pool's reader connections. That is the whole reason the app's
handle is a pool: the screen's read never waits behind a long write. The writer is a `let` precisely
so that snapshot can reach it without actor isolation.

The row SQL and mapping are shared between the single-purpose accessors and the bulk snapshot, so the
two cannot drift apart.

---

## What is not here

The schema is the target state, not a history. Tables that earlier versions created and later dropped
are simply absent from the object list, and a phone that still has them keeps its rows: nothing in the
install path deletes anything.

Two artifacts of that are worth knowing.

The in-memory batch type still carries fields for streams whose tables are gone. The insert path
persists only the two that exist, deliberately, so a write cannot throw and abort the transaction that
also carries live beats.

The body-clock phase store used to be the counter-example: a file that still compiled and queried a
table the schema no longer creates. It was deleted along with the read wrapper above it, so the
package no longer names a table it does not build.

---

## Tests

The suite lives in `Packages/CenitStore/Tests/CenitStoreTests/` and runs entirely against in-memory or
temporary databases, so `swift test` in this package needs no simulator, no HealthKit and no device.

Two of its cases carry unusual weight. A **shape test** compares the installed `sqlite_master` against
the reference dump character for character, which is what makes the verbatim DDL worth the awkwardness.
And a **legacy-fixture test** opens a checked-in database built by the previous incremental history
and asserts that opening it executes no schema statement and loses no row.
