# Branch and PR triage — 2026-10-11

Main is the application baseline. This change brings forward previously successful
integration dependency updates: shared_preferences 2.5.6, geolocator 14.1.1,
setup-java v6, upload-artifact v7 and gitleaks v3. Application changes on main are retained.

- PR #14: historical connection branch; its BLE/UI work has been superseded by main.
  Closed the PR; its source branch is preserved for recovery.
- PR #1: substantial alternate app implementation, not a small integration patch.
  Converted to draft for explicit feature extraction; bulk merge would replace current
  generated protocol code and feature workflows.
- PR #41: universal_ble 2.3.0 Android Gradle migration fails with the current toolchain.
  Defer until a dedicated Kotlin/Gradle migration passes Android CI.
- PR #42: flutter_foreground_task 11.0.3 requires Dart >=3.12; pinned CI has Dart 3.11.3.
  Defer until a dedicated Flutter/toolchain upgrade is validated.
- PR #38: checkout v7 has Android success but emulator failure; retain pending investigation.

Do not delete the 46 historical branches wholesale. Preserve beta and alternative-feature
branches. Reconcile integration with main only after the feature PR is accepted, then
retarget dependency work to main. Rewriting history changed commit IDs; old clones must
be replaced or rebased carefully to avoid restoring removed attribution.
