# Bastion app feature development milestones

Status reconciled 2026-10-20 against main `68abe898` and the v0.1.3-beta.1 release.

Application baseline: `main`. Preserve `feature/bastion-beta`; see [release readiness](RELEASE-READINESS.md) for exact-artifact gates.

**Evidence boundary:** Checked items below describe implemented capabilities, not universal hardware certification. Automated and owner-reported device evidence is recorded in [release readiness](RELEASE-READINESS.md). Open items identify remaining work or verification.

**Definition of done:** implementation wired into the app UI and live services; unit/widget tests; CI green; physical-radio verification where applicable; documented limitations. A codec or standalone service alone is **not** a finished feature.

## Milestone A1 — radio configuration and BLE reliability
- [x] Draft node-name editor, validation, owner payload encoding, local admin packet transport helper, and fresh NodeInfo readback helper
- [x] Transport-independent bounded reconnect supervisor and tests
- [x] Confirm ADMIN_APP schema and firmware-specific session authentication against official firmware — generated from `meshtastic/protobufs` v2.8.1; session passkey handled; owner and channel writes verified on firmware 2.7.16
- [x] Admin responses, negative acknowledgments, timeouts and verified editor saves — `MeshtasticAdminSession` handles responses and transactions; PR #51 adds fresh same-radio readback and PR #52 preserves drafts/submitted snapshots. Bulk channel imports retain a separate transaction flow; see [save verification](SETTINGS-SAVE-VERIFICATION.md).
- [x] Enable Save only when authenticated, connected, and explicitly confirmed
- [x] Integrate reconnect supervisor into actual BLE lifecycle; respect manual disconnect and Android Bluetooth state — integrated and respects manual disconnect; Android Bluetooth off/on waiting and recovery are implemented
- [x] Add Android foreground service and notification permission flow for background connectivity
- [ ] Physical radio tests on supported firmware and Android versions — passed on one radio (firmware 2.7.16); more firmware and Android versions still to cover

## Milestone A2 — messaging and node intelligence
- [ ] Delivery-state correctness, offline queue reconciliation, channel and DM UX — routing ACK delivery states and per-node DM threads done; offline queue reconciliation not re-verified
- [x] Node favorites, notes, telemetry, signal history, traceroute and neighbors — favorites, notes, telemetry requests and traceroute (per-hop SNR) done; neighbor reports and map links are implemented
- [ ] Protocol fixture tests and live radio verification — fixture tests cover admin, traceroute, channel links, nodes, positions and waypoints; live verification partial

## Milestone B1 — maps, GPS, field operations
- [x] Offline map tiles, location permissions, node positions, waypoints — viewed OpenStreetMap areas cached offline for a year (no bulk area downloads under the OSM tile policy)
- [x] Check-in/assistance/all-clear templates with explicit review and delivery disclaimers; persisted incident logs and CSV export — see [field features](FIELD-FEATURES-AND-TESTING.md).
- [ ] Privacy controls and battery-aware tracking — phone GPS sharing is opt-in and throttled; no wider privacy settings yet

## Milestone B2 — bot and RF field tools
- [x] Bot opt-in, command handling, anti-loop checks, quiet hours and persisted reply-attempt limits; selected-channel eligibility and fail-closed storage behavior
- [x] Opt-in receiver-location/SNR/RSSI observations, bounded local history and CSV exports
- [ ] Terrain-assisted link planning

## Milestone C1 — backups, firmware and interface
- [x] Encrypted radio settings backup/restore with explicit password and key handling — fresh reads, preview, confirmation, reconnect/readback; excludes device identity keys, session credentials and phone history; device failure can leave partial changes
- [ ] Firmware capability checks, maintenance and supported upgrade path
- [x] Light/dark/system theme, message notifications, dashboard visibility preferences and large-text layout improvements
- [ ] Broader device accessibility and Android navigation-mode acceptance

## Milestone C2 — Bastion exclusive features
- [ ] Network health scores and explainable recommendations
- [x] Local field observation history and CSV export
- [ ] Validated dead-zone predictions
- [ ] Optional BackCountrySignal integration with opt-in sharing

## Also delivered outside the milestones
- Every config section and module editable through a generated settings form
- Channel sharing as `meshtastic.org/e/#` links and QR codes, including camera scanning

## Release gates
- No claim of full official-app parity until every required feature is integrated and tested
- No automated release or Play publication without signing, privacy review and approval
- Real BLE and radio behavior cannot be certified by emulator or Flutter unit tests

## Historical completion update — 2026-10-11 (superseded by the status above)

The owner reports earlier reliability items 1–3 completed. Hardware models/versions and test results were not supplied; retain independent-verification gates. At that time, main lacked automatic post-save readback; PR #51 subsequently added it. Chat now selects enabled radio channels and searches all retained history. At that time, production signing was prepared and signed-artifact QA was pending; later release evidence is recorded below. Play account setup remains open.

## Current next steps — 2026-10-20

1. Validate the repaired PR secret-scan read permissions, then update and validate the Dependabot PR (#53).
2. Extend exact-signed-artifact testing to a second radio and more Android versions; include interrupted writes, QR round-trip, secondary-channel delivery and screen-off recovery.
3. Reassess the PR #1 extraction list against delivered bot/coverage work before adapting remaining radio-scoped history, local alerts or map-pack import. Do not replace main with the alternate application.

The latest published beta is [v0.1.3-beta.1](https://github.com/charlottemeshtastic/Bastion-Meshtastic/releases/tag/v0.1.3-beta.1). Its release notes record owner verification of the exact signed candidate on a T1000-E; this does not certify all devices or every acceptance scenario.
