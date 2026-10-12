# Branch and PR reconciliation — 2026-10-12

Main is the application baseline. This maintenance change retains PR #47's settings
fixes, encrypted backups, chat controls, signing preparation and emulator checks.
The published v0.1.1-beta.1 tag and APK remain unchanged.

## Integration and dependency work

The maintenance PR merges feature/bastion-v1-integration history, including PR #46's
GPL-3.0 license and PR #38's checkout v7 update. Conflicts retain the main application's
source, release/signing workflows and smoke-test script.

Original PR #41 and #42 branch histories are also included. Upgrade universal_ble to
2.3.0 and flutter_foreground_task to 11.0.3 with Flutter 3.47.7 across CI. The foreground
package requires Dart >=3.12 / Flutter >=3.44; both packages use Android built-in Kotlin.
The pinned Flutter Android template supplies built-in Kotlin, AGP 9.1.0 and Gradle 9.3.1.
No dependency cache patches or alternate application implementation are introduced.

Dependabot and nightly validation target main. After analysis, tests, APK/AAB builds
and emulator startup pass, merge the maintenance PR and fast-forward integration to
that same main commit. Retarget dependency PRs to main before final reconciliation.
Their original heads are retained as ancestors, so the histories can be reconciled
without deleting their source branches or force-pushing.

## PR #1

PR #1 at e920e36f90cc69120ff7973a81b112b2fdbdbeed is a substantial alternate app, not a
small patch. Its shell, models, native activity/service and protocol generation must
not replace main's current settings, traceroute or encrypted backup implementation.
[The feature review](PR1-FEATURE-REVIEW.md) identifies useful work to adapt individually.
Keep the PR and codex/local-automations branch available for those extractions.

## Validation boundary

The owner's T1000-E test covered the published beta's original dependencies. After
this dependency migration, repeat scan/connect, reconnect, Bluetooth off/on and
locked-phone/background checks on a radio. CI does not extend that hardware result
by itself. Historical beta and alternate-feature branches remain preserved.
