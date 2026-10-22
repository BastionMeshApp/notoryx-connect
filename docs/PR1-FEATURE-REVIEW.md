# PR #1 feature review — 2026-10-12

Reviewed [PR #1](https://github.com/charlottemeshtastic/Bastion-Meshtastic/pull/1) at
commit e920e36f90cc69120ff7973a81b112b2fdbdbeed, branch codex/local-automations.
This identifies useful feature candidates; it does not claim they are integrated
into main or hardware verified.

**Status 2026-10-21:** candidates 2 and 4 are delivered on main through PR #49
(`bastion_bot_guard.dart`, `bastion_field_log.dart`); do not port them again.
Candidate 1 is implemented on main (`bastion_radio_history.dart`, per-radio NodeDex). Candidate 3 is implemented as Settings → Field alerts (`bastion_field_alerts.dart`). Candidate 5 remains. PR #1's head `e920e36f` now passes CI with 81 tests
and builds an APK ([run 38156061289](https://github.com/charlottemeshtastic/Bastion-Meshtastic/actions/runs/38156061289)),
so its description's "no APK" note is outdated.

## Recommended extraction order

| Priority | Work worth adapting | Source in PR #1 | Main destination and required checks |
|---|---|---|---|
| 1 (done, main) | Radio-specific chat/node history | lib/services/messaging/chat_history.dart; lib/services/node_archive.dart; lib/models/telemetry_sample.dart | Adapt bastion_message_archive.dart, bastion_nodedex.dart and coordinator queries. Preserve existing records until radio attribution is established; test radio switching, duplicates, failed writes and bounded retention. |
| 2 (done, #49) | Persisted bot attempt limits and selected-channel commands | lib/services/bot/bot_engine.dart; bot_controller.dart | Adapt bastion_bot_rules.dart and meshtastic_messaging_service.dart to the main message model. Keep opt-in behavior, radio arming, sender validation, stale/duplicate/replayed packet suppression and channel-role checks. Port policy tests and verify actual-service wiring. |
| 3 (done, main) | Local battery, new-node and silence alerts | lib/services/automations/automation_engine.dart; automation_controller.dart | Feed a small rules service from verified main coordinator/telemetry observations. Inject a clock; test one-alert-until-recovery, reconnect seeding and suppression while disconnected. Local alerts should not automatically transmit messages. |
| 4 (done, #49) | Receiver-location/SNR/RSSI observations and CSV | lib/services/field/coverage.dart | Adapt mesh tools using existing GPS and telemetry boundaries. Preserve opt-in location, fresh/accurate fixes, connected-radio identity, MQTT exclusion, packet freshness and rate limits. Label observations accurately, without unverified coverage predictions. |
| 5 | User-imported offline map packs | lib/services/field/offline_maps.dart; android_support/FieldFiles.kt; lib/screens/map/offline_maps_page.dart | Adapt the picker/tile provider to bastion_tile_cache.dart and map_page.dart. Preserve attribution, ZIP path/size/tile bounds, staging and cancellation. Test interrupted/invalid import and recovery of the previous pack. |

## Concrete behavior worth retaining

The bot reserves attempts before Bluetooth writes and persists per-radio/per-peer
attempts. It applies sender cooldown, global spacing and hourly limits, restricts
channel replies to selected commands and rejects stale/duplicate/bot-marked packets.
This complements main's anti-loop and Store & Forward replay protections.

The automation engine ignores older observations, does not treat unknown battery as
low battery and rearms an alert after recovery. Silence checks require a connected
radio. The controller seeds known nodes to prevent a reconnect alert for every node.

Coverage recording binds a fresh receiver fix to fresh radio observations, excludes
MQTT-origin reports, stops on session changes or persistence failure and bounds its
history. It provides CSV output rather than treating samples as predicted coverage.

Map import uses a user-selected document, staged extraction, tile paths limited to
z/x/y.png, metadata validation and compressed/expanded size limits. It supports local
map packs; it is not permission to bulk-download arbitrary map-provider tiles.

## Keep main's implementation

Main already has connection recovery, generated PhoneAPI/admin code, foreground
service, notifications, GPS sharing, node details, traceroute, channel QR support and
encrypted radio backups. Replacing these with the alternate connection manager,
MainActivity, native connection service or generator would create parallel code and
lose delivered features. Its charcoal/sage theme and launcher asset are separate
design options; dependency maintenance does not change branding.

## Migration boundary

Each extraction needs its service, UI, persistence migration and adapted tests in
one independently reviewable feature change. A copied standalone controller is not
a completed feature. Retain the source branch, attribution and license notices.
Do not claim that PR #1's storage format is compatible with main without migration
fixtures. This maintenance PR reviews and preserves those candidates; it does not
bulk-import their alternate application architecture.
