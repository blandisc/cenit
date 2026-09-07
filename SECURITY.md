# Security policy

## What the attack surface actually is

Cénit runs entirely on the device. It has no server, no account, no sync and **no reachable network
code at all** — not a disabled endpoint, not an opt-in upload, none. That removes the whole web
attack surface, and it also removes the classes of report that usually dominate: there is no
authentication to bypass, no session to hijack, no traffic to intercept and no third-party service
holding user data.

What remains is local, and it is short:

- **The SQLite database.** Every reading the app has ever computed or imported lives in one file in
  the app's sandbox, protected by iOS Data Protection and the device passcode.
- **Files the user opens.** An Apple Health export archive, or a Cénit backup file. These are the
  only untrusted input the app parses.
- **Files the user exports.** Backups and comma-separated exports are written in plaintext to a
  destination the user picks.
- **The app group.** A small, structured channel between the app, its widget extension and its Live
  Activity.

[`docs/PRIVACY_SECURITY.md`](docs/PRIVACY_SECURITY.md) documents each of these in detail, with the
commands to verify the network claim yourself.

## What makes a good report

The most valuable report against this codebase is **evidence that the offline guarantee is false** —
a reachable code path that opens a connection, or a way to flip the one dormant media-download gate
at runtime. That gate is a computed property returning a constant; showing that it can return true in
a shipped build would be a genuine finding.

After that:

- A crafted import file that corrupts the database, exhausts the device, or achieves code execution.
- A path that lets one app-group participant read or write more than its documented channel.
- Anything that causes health data to be written somewhere the user did not choose.

## Reporting

Open an issue on the repository.

If a public report would put people at risk before a fix can ship, open the issue with a short,
non-exploitable summary — what is affected and how severe — and hold the proof-of-concept details
until a fix is released.

Include what you can:

- What the issue is, and which guarantee it breaks.
- How to reproduce it.
- What an attacker gains.
- A suggested fix, if you have one.

This is a single-maintainer project. There is no guaranteed response time. Confirmed issues are
prioritized for the next release.

## Which versions get fixes

Only the latest release receives fixes. If you build your own copy, rebuild from the latest tag to
pick up security fixes.

## Not a vulnerability

- **Physical access to an already-unlocked device.** The app adds no second factor over the device
  passcode: no in-app lock, no biometric gate, no separate database passphrase. Someone holding an
  unlocked phone has the data, and that is a documented property rather than a defect.
- **Where the user puts an export.** Backups and exports are plaintext by design, and the app cannot
  control the destination the user chose.
- **Third-party dependencies.** Report those upstream. The complete list is two libraries, both
  local-only; see [`NOTICE`](NOTICE) for their licenses.
