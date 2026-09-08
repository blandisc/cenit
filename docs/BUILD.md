# Building and running Cénit

Cénit builds with the standard Apple toolchain and nothing else. There is no package manager to
install, no code generation step beyond the Xcode project itself, and no secrets or API keys to
provision — the app has no server to talk to.

There are two loops, and knowing which one you are in saves most of the waiting.

- **The package loop** is `swift build && swift test` inside a directory under `Packages/`. It needs
  no Xcode project, no simulator and no signing, and it finishes in seconds. Everything that is
  math, persistence, domain logic or design-system code can be changed and proven here.
- **The app loop** builds the real target through `xcodebuild`. It takes minutes and is memory
  hungry. You need it only when the change touches the app layer.

Prefer the first. Reach for the second when you have to.

---

## What you need

| Tool | Version | Why |
| --- | --- | --- |
| macOS | 26 or newer | The design system uses iOS 26 SDK APIs. |
| Xcode | 26.x | Same reason. Verify with `xcodebuild -version`. |
| XcodeGen | 2.45 or newer | The Xcode project is generated, not committed. Install with `brew install xcodegen`. |

Swift 5.9 tools are the floor declared by every package manifest; the toolchain shipping with Xcode
26 is well past it.

A paid Apple Developer account is **not** required. Building for the simulator needs no signing at
all, and installing on your own iPhone works with a free personal team.

---

## Generating the Xcode project

`Cenit.xcodeproj` is generated from `project.yml` and is deliberately not in version control — it
is listed in `.gitignore` alongside the rest of the build output. Regenerate it after cloning, and
again any time you add or remove a file or edit `project.yml`:

```bash
xcodegen generate
```

Forgetting this is the most common cause of a build that fails on a file you can plainly see in the
repository.

---

## The package loop

From any package directory:

```bash
cd Packages/CenitAnalytics && swift build && swift test
```

To run a single case or method:

```bash
swift test --filter RecoveryScorerTests
```

Every package's tests run against pure values or an in-memory database, so none of them need a
simulator, a device, or Apple Health.

---

## Building the app

The unsigned simulator build is the fastest way to prove the app layer still compiles:

```bash
xcodebuild build-for-testing -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS="" ASSETCATALOG_COMPILER_APPICON_NAME="" -jobs 4
```

Two details in that line are not optional.

Use `build-for-testing`, not plain `build`. Plain `build` never compiles the test targets, so a
test file left behind by a signature change stays broken while the build reports green.

Use the **scheme**, not a target. The scheme pulls in the widget extension and the watch app; a
target build compiles neither.

### Running the app's unit tests

The app's unit tests are the one thing that genuinely needs a **signed** build. An unsigned binary
compiles fine but cannot run: without the App Group entitlement the app trips its own startup
assertion and dies before the first test executes, which reports as an early unexpected exit rather
than as a failure. So:

```bash
xcodebuild build-for-testing -project Cenit.xcodeproj -scheme Cenit -destination 'generic/platform=iOS Simulator' -configuration Debug -allowProvisioningUpdates -jobs 4
```

then run against a booted simulator:

```bash
xcodebuild test-without-building -project Cenit.xcodeproj -scheme Cenit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CenitUnitTests -jobs 4
```

In practice you should not type any of this. See the next section.

---

## `Tools/verify.sh` — the one command

`verify.sh` encapsulates the whole choreography: the linters, the right packages, the app build when
it is warranted, the wait-for-idle, the job cap, the DerivedData prune and the simulator lifecycle.
Run it before finishing any change that touches Swift.

```bash
Tools/verify.sh
```

| Mode | What runs |
| --- | --- |
| *(none)* — auto | Linters, then build and test each touched package, then an unsigned app build if the app layer changed. |
| `quick` | Linters only. |
| `package <Name>` | Linters, then that one package. |
| `packages` | Linters, then every touched package. |
| `app` | Linters, then the unsigned app build. |
| `app-tests` | Linters, then a signed build and the unit tests on a simulator. |

Anything else is rejected. Every failure exits 1 with a message prefixed `✋ verify:`; success exits 0.

Two behaviors are worth knowing before you rely on auto mode.

**It decides what is "touched"** from the union of your diff against the merge base with `origin/iOS`
and your dirty working tree. If `origin/iOS` was never fetched, only the working tree counts.

**Auto mode does not build the app for every change.** The app-layer test covers `Cenit/`,
`CenitApp/`, `CenitShared/`, `CenitWidgets/`, the app test folders and `project.yml`. A change
confined to `CenitWatch/` or to `Packages/` does not trigger it — the watch is not in that list, and
package changes run their own package build instead.

Also note that `quick` deliberately does **not** write the completion stamp, because linters alone
are not verification.

### The design-system linters

Most of what `verify.sh` runs is the design-drift linter, in two flavors. Diff-scoped rules check
only the files you changed. Ratchet rules scan whole directory roots against a committed baseline,
because their budgets are per-file — which means pre-existing debt in a file you did not touch can
fail your run. That is intended: the baseline may only ever go down.

The escape hatch for a genuinely justified violation is a per-line comment naming a category and a
reason. A separate gate proves that the rules and roots used locally, in the pre-commit hook and in
continuous integration are identical, so "green here, red there" cannot happen silently.

---

## Machine hygiene

This is not incidental advice. Ignoring it is the leading cause of a build that takes the whole
machine down.

**Always pass `-jobs 4` to a full app build.** An uncapped `xcodebuild` fans the compiler across
every core; on a 16 GB machine that exhausts memory. `verify.sh` passes it for you.

**Never run two full builds at once.** Your `xcodebuild` racing the Xcode GUI, or two agent sessions
building simultaneously, is the single most common way to run the machine out of memory, and the job
cap does not make it survivable. Wait for the machine to go idle first:

```bash
while pgrep -q swift-frontend; do sleep 30; done
```

`verify.sh` does this itself, with a thirty-minute ceiling — if the wait times out, someone is
probably building in Xcode. Keep waiting rather than racing them.

**Prune DerivedData before a full build.** Every worktree mints its own folder of roughly a
gigabyte, and those outlive the worktree.

```bash
Tools/prune-deriveddata.sh
```

It deletes only folders whose checkout no longer exists, and it is safe to run with Xcode open.
`verify.sh` calls it before an app build.

**Shut down the simulator when you are done.** A booted simulator keeps running headless, holding
roughly eight gigabytes, even with the Simulator app closed — and starves the next build.

```bash
xcrun simctl shutdown all
```

**Clean up when you finish an issue.** One command prunes delivered worktrees and the DerivedData
they left behind; run it without the flag first for a dry run.

```bash
Tools/cleanup.sh --apply
```

It is careful about what it removes: it keeps your own worktree, anything a live process is sitting
in, anything locked, anything with uncommitted changes, and any branch whose upstream still exists.

---

## Installing on your iPhone

Open the generated project in Xcode, select your device, and run. With a free personal team,
`project.yml` already carries automatic signing, so Xcode provisions on first build. The
seven-day expiry of a free personal profile applies as usual.

The app requests HealthKit read access on first launch and asks to write workouts only when you turn
that setting on. Clinical-records access is deliberately not requested.

Building to a device is an owner action and is not part of the verification flow. Nothing in this
repository automates it, and no change is considered unfinished because it has not been installed on
a phone.

---

## Hot reload

`project.yml` keeps the flags that InjectionNext and InjectionIII need: the interposable linker flag
and the frontend-command-line emission that the injection tool reads, both Debug-only. The
`INJECTION_PROJECT_ROOT` environment variable is set on the Run scheme so the injection bundle
watches the whole source tree — without it, only edits saved inside Xcode's own editor are noticed,
and edits made by any other tool are invisible.

The injection integration itself is a small local shim guarded by `#if DEBUG`; the Release branch
compiles to a no-op.

---

## Continuous integration

Six workflows exist. Only two of their jobs are required to merge.

| Workflow | Runs when | What it does |
| --- | --- | --- |
| **Design Lint** | Every pull request, no path filter | The design-drift rules, the gate-parity check, the teaching-registry check, the Python gate self-tests, and a job that proves the drift baseline only went down. **Both of its jobs are required.** |
| **Swift Packages** | Changes under `Packages/**` | Builds and tests seven packages in a matrix, three of them on Linux. |
| **iOS App** | Nightly, on manual dispatch, or on a pull request carrying the `ci-app` label | Compiles the app ad-hoc signed with entitlements intact, then runs the unit tests on a simulator. |
| **Design Tokens** | Changes to the design system or its generated docs | Runs the design-system tests, regenerates the tokens, and fails if the committed output differs. |
| **i18n guard** | Changes to app or package sources | Catches Spanish literals in code, forbidden dashes in Spanish strings, and keys missing a Spanish localization. Runs its own extractor self-test first. |
| **Release** | A `v*` tag | Builds an unsigned device binary and publishes it. |

The app workflow is opt-in because macOS runners bill at ten times the Linux rate. Apply the
`ci-app` label to any pull request that touches the app layer — but apply it **after** the pull
request exists. Passing it at creation time has repeatedly caused the labeled run to be cancelled by
the concurrency group, leaving a job that reports as skipped without ever having run.

---

## When something goes wrong

**A file you can see does not compile.** Run `xcodegen generate`.

**The build reports success but a test file is stale.** You used `build`, not `build-for-testing`.

**The unit tests die before the first test runs.** The build was unsigned, or entitlements were
stripped. Use `Tools/verify.sh app-tests`.

**The machine runs out of application memory.** Two builds were running. Wait for
`swift-frontend` to disappear, then retry with `-jobs 4`.

**An incremental build does not pick up a package edit.** The app build keys off object-file
timestamps and can miss a change inside a package. Build the package directly to confirm, then force
the app build.

**Contrast tests fail locally but pass in CI.** Check whether your Mac is in dark mode.

**Swift package fetching fails.** A local `GIT_CONFIG` override is the known workaround.
