# Privacy and security

Cénit's privacy claim is unusually simple: **the app has no network path.** Not "no telemetry", not
"no tracking" — no reachable code that opens a connection. There is no server, no account, no sync
and no analytics, so there is no data flow to audit, only an absence to verify.

This document sets out the evidence for that claim, then describes everything the app *does* do with
the user's data: what it reads from Apple Health, what it writes back, where it stores things, what
crosses a process boundary, and what it deliberately does not have.

Every claim here is checkable against the tree. Where something could not be verified, it says so.

---

## 1. The network claim, and how to check it

Sweep the entire source tree — the app, the widgets, the watch app and all eight packages — for
every way iOS can open a connection:

```bash
grep -rn 'NWConnection\|NWPathMonitor\|import Network\|CFNetwork\|WebSocket\|dataTask\|downloadTask\|uploadTask\|URLRequest\|WKWebView\|AsyncImage' \
  Cenit CenitApp CenitShared CenitWidgets CenitWatch Packages --include='*.swift'
```

That returns **nothing**. No `Network` framework, no low-level sockets, no web view, no
`AsyncImage`, not even a `URLRequest` type.

`URLSession` appears in exactly one file — `Cenit/Media/MediaDownloadCoordinator.swift` — as a
stored property and an injectable initializer parameter, with two call sites that could issue a GET.
Both sit behind a single gate:

```swift
var isEnabled: Bool { false }
```

That is a computed property returning a literal. It reads no preference, consults no build flag and
has no setter. Both call paths return early before touching the session.

The gate is belt and braces. The preference key that once controlled this feature is deliberately
excluded from the app's key registry, and the launch-time preference migration **deletes** both
spellings of it rather than carrying them forward. A restored backup that has the flag set to true
cannot switch networking on. Beyond that, the bulk download path has no production caller at all —
its only invocation in the tree is from a unit test, which asserts that the feature stays off even
when the preference is explicitly set true, that a bulk run leaves the state idle, and that an
on-demand fetch resolves to nothing.

The images the exercise screens show come from files bundled inside the app instead.

### URLs that exist but are not requests

Several literal URLs appear in the source. None of them is fetched by the app.

| Where | What it is |
| --- | --- |
| Terms, privacy and support links | SwiftUI `Link` destinations. Tapping one hands the URL to Safari; the app issues no request. |
| A search URL on the exercise detail screen | Passed to `openURL` as a fallback when no local media exists. Same hand-off. |
| A media CDN URL built in the training package | A string synthesized into a model field, consumed only by the dormant coordinator above. |
| `x-apple-health://`, the iOS settings URL, and the app's own `cenit://` scheme | Local schemes. They open the Health app, the Settings app, or Cénit itself. |
| Package repository URLs | Build-time only, read by SwiftPM. |

App Transport Security is **not configured** — there is no exceptions dictionary anywhere. The iOS
defaults therefore apply in full. That is the correct posture for an app that issues no requests:
there is nothing to grant an exception to.

---

## 2. What the app is permitted to do

### Entitlements

Four entitlement entries exist across three targets. That is the complete list.

| Target | Entitlement | Value |
| --- | --- | --- |
| App | `com.apple.developer.healthkit` | true |
| App | `com.apple.security.application-groups` | one group |
| Widget extension | `com.apple.security.application-groups` | the same group |
| Watch app | `com.apple.developer.healthkit` | true |

Absent, and worth naming because their absence is the security property:

- **Clinical health records access.** Deliberately not requested. The app never reads clinical
  records.
- **Push notifications.** No push entitlement, no remote-notification registration, no push token.
- **iCloud containers.** None. The automatic backup writes to a folder the user picked, which iCloud
  Drive may then sync on its own; the app has no iCloud capability of its own.
- **Keychain access groups.** None — the app stores no credentials at all.

The iOS app declares **no background modes**. It computes only while open: there is no background
task scheduler, no HealthKit background delivery, and no silent push. The watch app declares
workout processing, which is mandatory for any live workout session.

### Privacy manifests

Three manifests ship, one per binary. All three declare `NSPrivacyTracking` false, and none declares
tracking domains — the key is absent entirely, not present and empty.

The **app** manifest declares one collected data type: health and fitness, marked linked to the user,
not used for tracking, and used only for app functionality. It declares two accessed API categories:
user defaults, and disk space. The widget and watch manifests declare no collected data at all, and
only the user-defaults category.

Each declared reason is substantiated by real code. The user-defaults declaration covers the
app-group-scoped preferences the three processes share. The disk-space declaration covers exactly one
call: the Apple Health importer checks available capacity before decompressing an export, so it can
refuse a job that will not fit rather than filling the device.

> The app manifest's inline comment cites a file and line for the disk-space check that no longer
> matches where the call lives. The declaration itself is correct; only the pointer is stale.

---

## 3. Health data

### What is read

The app requests read access to sixteen HealthKit types: heart rate, resting heart rate, heart-rate
variability, oxygen saturation, respiratory rate, step count, active and basal energy, VO₂ max,
wrist temperature during sleep, sleep analysis, workouts, the beat-to-beat heartbeat series, biological
sex, date of birth, body mass and height.

The heartbeat series deserves a note. It is what makes on-device nocturnal variability possible from
raw intervals rather than from a vendor's summary, and HealthKit requires it be requested alongside
the variability type. Installs that predate it get a one-time supplementary request for those two
types only.

The authorization call passes an **empty share set**: connecting Apple Health asks for read access
and nothing else.

### What is written

Two types, requested separately and only when the user turns on the corresponding setting: workouts,
and active energy.

The write is gated twice — by a preference that defaults to off, and by a live authorization check
immediately before saving. What it writes is one strength-training workout carrying one active-energy
sample and an external identifier. That energy figure is a **MET-based estimate**, not a measurement;
the heart rate collected during a session feeds the estimate and is explicitly never written back to
Apple Health as heart-rate samples.

Deletion is scoped by a compound predicate to objects this app itself wrote for that specific session.
It exists so re-saving is idempotent, not so the app can clean up anything it did not create.

The watch app requests read access to heart rate, active energy and workouts, and share access to
workouts and active energy, so it can run a real workout session and mirror it to the phone.

---

## 4. Data at rest

### Where it lives

One SQLite file inside the app's sandbox, at `Application Support/Cenit/cenit.sqlite`, with the usual
write-ahead-log sidecars beside it and the media cache in the same container. Installs created before
the rename carry the previous folder and filename; a one-time migration at launch moves them, and that
migration renames sidecars first and the main file last, so the main file's name is the mark of
completion and an interrupted run simply resumes.

### Encryption

**The app applies none of its own.** There is no SQLCipher, no passphrase, no application-layer
cipher, and no explicit Data Protection class set on the file. The one CryptoKit import in the tree
computes a SHA-256 string used as a sync fingerprint — a hash, not encryption.

What protects the file is therefore the platform default for its container, applied by iOS rather
than by this code: it is readable only after the device has been unlocked once since boot, and it is
covered by the device passcode. The declaration that the app uses no non-exempt encryption is
consistent with this: it ships no cryptography of its own.

### Backup

The database is **not** excluded from device backups — there is no exclusion flag anywhere in the
tree. It is therefore included in iCloud and encrypted local backups, which is the intended
behavior: it is the user's only copy of years of history.

---

## 5. Export and backup features

Three mechanisms let data leave the sandbox, all user-initiated, none encrypted by the app.

**Manual export.** Produces a dated copy of the live SQLite file. It stages into the temporary
directory and hands the file to the system document picker, so the user chooses where it lands. It
requires a successful write-ahead-log checkpoint first and fails loudly rather than producing a
partial file. Import validates the SQLite magic header, snapshots the current database before
replacing it, removes stale sidecars before the atomic swap, and requires a relaunch.

**Automatic backup.** Copies the database to a folder the user picks once, rotating the previous copy
aside, at most once per day. Access to that folder persists as a security-scoped bookmark and the
write goes through a file coordinator. This is not an iCloud feature — the app writes to a local path,
and any off-device sync happens because the user chose a folder that iCloud Drive itself syncs.

**Text and image exports.** Comma-separated exports and a rendered session card, written to the
temporary directory and presented through the system share sheet, with the temporary file cleaned up
afterwards. The image path is the sole reason the app declares add-only photo-library access.

All three produce plaintext. A backup file is exactly as sensitive as the database it copies, and
protecting it is the user's choice of destination.

Reading an archive uses ZIPFoundation in read mode only, in the Apple Health importer. Nothing in the
codebase writes a zip.

---

## 6. What crosses a process boundary

The app, the widget extension and the watch app are three processes. The app group is the only
channel between the first two, and everything on it is small and structured.

| Channel | Carries |
| --- | --- |
| Live Activity action inbox | Queued button presses from the lock screen: add or remove thirty seconds, skip, complete a set, finish, resume. Written by the extension, drained by the app, woken by a payload-free Darwin notification. |
| Widget snapshot | What the widget renders: today's routine name, whether a session is live, the verdict's tone and word, and the week's day states. |
| Shortcuts inbox | Pending intents fired while the app was closed. |
| Rest thumbnail | A single already-cached image file, copied so the widget process can render it. Never fetched. |

The Live Activity's content state does carry two health values — the current pulse and a target — 
alongside session and exercise names. The Activity is requested with **no push type**, so no push
token is minted and nothing is transmitted to Apple's push servers. It is a local-only Live Activity.

Note what this means for the widget extension: it holds only the app-group entitlement, not HealthKit.
It cannot read health data directly. It sees exactly the snapshot the app chose to write.

---

## 7. What the app does not have

Verified absent by sweeping the tree. Each of these is a category of risk that simply does not exist
here.

| Absent | Consequence |
| --- | --- |
| Keychain use of any kind | No credentials, tokens or keys are stored. There are none to store. |
| Analytics, crash reporting or telemetry SDKs | No third-party code observes the user. |
| Location, camera, microphone, contacts | No such API is used and no usage string is declared. |
| Photo-library **read** | Only add-only write, for saving a session card. |
| Bluetooth | Removed with the external-device support it served. |
| Remote notifications | No token, no registration, no server to send one. |
| Web views | No embedded browser surface. |

### Logging

Five loggers exist. The file that reads every health sample contains **no logging at all** — no
logger, no `os_log`, no `print`.

Nineteen log sites mark their interpolation public. Every one was inspected: each interpolates either
a file or folder name, or an error description. No health measurement is interpolated into any log
statement. A handful of plain `print` calls elsewhere emit counts, elapsed milliseconds, a database
path and identifiers — never a heart rate, a variability figure or a sleep value.

### Preferences

The app's keys live under a single `cenit.` namespace in a central registry: onboarding and terms
state, appearance, three session preferences, the backup bookmark and its metadata, selected calendar
identifiers, a mirroring toggle, and the app-group intent inbox. A few keys live outside that registry
in the HealthKit bridge — the connection flag, the write opt-in, a sync fingerprint hash and a
one-time request flag.

**No health measurement is stored in preferences.** They hold flags, names, dates, a bookmark, a hash
and UI state. A migration copies then deletes every key from the previous naming scheme.

### Calendar

The app can read the phone's calendars, to relate stress patterns to what was on the schedule. Two
usage strings declare it, the user grants it explicitly, and the selected calendar identifiers are
the only thing persisted. Nothing leaves the device.

---

## 8. Dependencies

Two third-party libraries ship in the app. Both are local-only.

| Library | Version | Purpose | Network |
| --- | --- | --- | --- |
| GRDB.swift | 6.29.3 | SQLite persistence and migrations | None — a SQLite wrapper over local file I/O |
| ZIPFoundation | 0.9.20 | Reading the user's own Health export | None — local archive reading |

A third, swift-syntax, exists only under a developer tool and is never linked into a shipped target.

> The generated Xcode project's resolved-package file still pins a retired hot-reload dependency.
> That file is build output and is not in version control; no target lists the package, and the
> remaining call sites resolve to a local debug-only shim whose release branch is a no-op.

---

## 9. Threat model

Given no network and no account, the realistic threats narrow to three.

**A hostile import file.** The Apple Health importer accepts a file the user supplies, which may be
arbitrarily large or malformed. It is streamed rather than loaded whole, runs behind a UTF-8 scrubber
because real exports contain invalid sequences, and checks available disk capacity before
decompressing so a decompression bomb fails a precondition instead of filling the device. The archive
library is used in read mode only.

**A stolen or unlocked device.** This is the dominant threat, and the app's answer is the platform's:
the database is protected by the device passcode through iOS Data Protection, and the app adds no
second factor. There is no in-app lock, no biometric gate, and no separate database passphrase. A
person with an unlocked device has the data.

**A careless export.** The export features write plaintext copies wherever the user directs them. A
backup placed in a shared folder is as readable as the database. The app cannot mitigate this beyond
requiring the user to choose the destination explicitly, which it does.

Not in the model, because the surface does not exist: server compromise, credential theft, session
hijacking, man-in-the-middle interception, and third-party data sharing.

---

## 10. Two discrepancies found while verifying this document

Both are comments that no longer match the code. Neither changes behavior, and both are recorded here
so a future reader does not cite them as evidence.

1. A comment in the backup code asserts reliance on a user-selected-files entitlement that no
   entitlements file or project configuration declares. That entitlement is a macOS sandbox key; the
   iOS document-picker flow used here does not require it.
2. The app's privacy manifest cites a file and line for its disk-space justification that no longer
   matches where the call lives. The reason code is substantively correct.

---

## 11. Reporting a security issue

Report a suspected vulnerability privately rather than by opening a public issue. See
[SECURITY.md](../SECURITY.md) for the current contact and expectations.

The most valuable report against this codebase would be evidence that the network claim in section 1
is false — a reachable code path that opens a connection, or a way to flip the media gate at runtime.
The verification commands in that section are the place to start.
