# Contributing to Cénit

Thanks for looking. Cénit is a fully offline health companion built on Apple Health: it syncs
HealthKit into an on-device SQLite database and computes recovery, effort, variability and sleep
locally. There is no server, no account, and **no reachable network code at all** — see
[`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md) for the evidence, including the commands to
check that claim yourself.

This page is orientation. The working guide — repository layout, where code belongs, the design-system
rules, how to add a metric, a screen or a migration, and the commit conventions — is
[`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md). Read that before opening a non-trivial pull request.

> Cénit is not a medical device. See [`DISCLAIMER.md`](DISCLAIMER.md).

---

## The fast loop

The codebase is eight cross-platform Swift packages under `Packages/` plus a thin iOS app layer. Most
real work happens in the packages, and they build and test on their own with no Xcode project, no
simulator and no signing:

```bash
cd Packages/CenitAnalytics && swift build && swift test
```

| Package | What it holds |
| --- | --- |
| `BiometricStreams` | The neutral shapes of a decoded sample. Foundation-only, the root of the graph. |
| `CenitModels` | Row types both storage and math need to name. |
| `CenitStore` | SQLite persistence, the schema and the migration that installs it. |
| `CenitAnalytics` | Every physiological computation, as pure functions. |
| `CenitTraining` | The strength domain plus the bundled exercise catalog. |
| `CenitImport` | Parsers for the files a user supplies. |
| `CenitDesign` | The SwiftUI design system. |
| `CenitEnsenanza` | The registry of what the app teaches and where. |

[`docs/LIBRARY.md`](docs/LIBRARY.md) is the reference for all eight.

## The app loop

The Xcode project is generated from `project.yml` and is **not** committed:

```bash
brew install xcodegen
xcodegen generate
```

Then open it, pick the `Cenit` scheme and run. [`docs/BUILD.md`](docs/BUILD.md) covers the toolchain,
installing on a device without a paid account, and the machine hygiene that keeps a full build from
exhausting memory.

## Verify before you push

One command handles the linters, the touched packages and the app build when it is warranted:

```bash
Tools/verify.sh
```

---

## What continuous integration checks

Six workflows run, but only two jobs are required to merge — both from the design-lint workflow, which
runs on **every** pull request with no path filter.

| Workflow | Runs when | Checks |
| --- | --- | --- |
| **Design Lint** | Every pull request | The design-system rules, the gate-parity check, the teaching registry, the gate self-tests, and that the drift baseline only went down. **Required.** |
| **Swift Packages** | Changes under `Packages/**` | Builds and tests seven packages, three of them on Linux. |
| **iOS App** | Nightly, on dispatch, or with the `ci-app` label | Compiles the app and runs its unit tests on a simulator. |
| **Design Tokens** | Design-system changes | Regenerates the tokens and fails if the committed output differs. |
| **i18n guard** | App or package source changes | Spanish literals in code, forbidden dashes, and keys missing a Spanish localization. |
| **Release** | A `v*` tag | Builds and publishes an unsigned binary. |

Apply the `ci-app` label **after** the pull request exists. Passing it at creation time has repeatedly
caused the labeled run to be cancelled, leaving a job that reports skipped without ever running.

If a check fails, fix the cause rather than routing around it. Never commit generated output such as
`Cenit.xcodeproj/`, and never commit secrets or keystores.

---

## Opening a pull request

1. One concern per pull request. Keep a schema change and a UI change apart.
2. Fill in the [template](.github/PULL_REQUEST_TEMPLATE.md).
3. For anything touching the math, add a test and cite the published method.
4. For anything touching a screen, use design-system tokens only. A literal color, font size or
   spacing value is a lint failure.
5. If the change moves the architecture, update [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) in the
   same pull request.

By opening a pull request you agree your contribution is licensed under the same terms as the project.
See [`LICENSE`](LICENSE).

---

## Reporting

- **Bugs and features** — open an issue using the templates in
  [`.github/ISSUE_TEMPLATE`](.github/ISSUE_TEMPLATE). Everything the app computes stays on your
  device, so leave anything that identifies you out of the report.
- **Security** — see [`SECURITY.md`](SECURITY.md). The most valuable report is evidence that the
  offline claim is false.

## Conduct

This project follows a [Code of Conduct](CODE_OF_CONDUCT.md). Keep discussion respectful and focused
on the technical work.
