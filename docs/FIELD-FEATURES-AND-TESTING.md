# Field features and device testing

This change adds app version 0.1.2+3. It is a test candidate; the existing v0.1.1-beta.1 release is unchanged.

## Settings availability

Radio settings → Settings availability checks configuration and module reads sequentially. Stop checking prevents further requests after the current read completes. Startup advertisements and successful admin reads show **Available**. A validated empty module/config response shows **Not returned by this radio**. A timeout or mismatched response shows **Read failed — retry**. Results reset on every connection. Missing startup advertisements remain **Not checked**. Entries remain accessible for a deliberate retry; no guessed hardware/firmware blocklist is used.

The Seeed T1000-E firmware 2.7.26.54e0d8d source reviewed earlier lacks Mesh Beacon/TAK get-module cases. This is evidence about that API implementation, not proof that every T1000-E or every beta build lacks a feature. Fixtures cover empty and valid Mesh Beacon/TAK replies, default-value advertisements, malformed data and unknown/missing sections. Existing admin tests cover wrong sender, wrong section, wrong response type and timeout.

## Appearance

Settings → Appearance & dashboard selects dark (initial default), light or system theme. The brand remains gold. Statistics, mesh health/signal and saved encounters can be hidden individually; radio scanning and live nodes remain accessible. Preferences persist on the phone. Text follows the system's text size; status switches to an icon with a spoken/tooltip label when text is large. Secondary text and disabled labels use theme colors, and dashboard values are not scaled down to fit.

## Field records

Tools → Incident log, emergency templates & coverage:

- **Incident log:** up to 500 private notes, attributed to the connected radio when available. Saves are durable before success is shown. Notes are removed only through an explicit confirmed removal. Copy incident CSV to export them.
- **Templates:** assistance, check-in and all-clear drafts. Replace the blank details, select an enabled channel and review the exact text/destination before sending. A ready unchanged radio is required. Limit is 220 UTF-8 bytes. These are ordinary messages; submission does not prove delivery or contact emergency services.
- **Coverage:** explicitly enable recording with a ready radio. Requests phone GPS without enabling mesh location sharing. Records receiver coordinates/accuracy, radio and sender IDs, packet ID, UTC time, SNR and RSSI. Only RF packets with receive times ≤2 minutes old and phone fixes ≤30 seconds old/≤50 m accuracy qualify. MQTT, self packets, invalid senders, duplicate packet IDs and nonfinite signal/location values are excluded. At most one reading per sender per 30 seconds. Keeps 2000 readings, expires readings after 30 days, stops on disconnect/GPS/storage failure, and never restarts automatically. The screen shows the latest 50; CSV includes all retained readings. CSV copying is an export to the clipboard; paste into a file/spreadsheet and save it.
- **Bot safeguards:** enable Bot Mode in Chats for this session. Quiet hours default to 22:00–07:00 in the phone's local time; equal start/end means quiet all day. Only the selected channel slot is eligible. Limits are six replies per hour, 30-second global spacing and five minutes per sender. Reservations persist before sends, including failed sends. Old/future/untimed messages, replays, invalid senders, messages addressed to other nodes and Bastion-prefixed responses do not qualify. Replies are direct messages. Storage failures block replies.

Phone field records are not encrypted. Coverage exports contain location history. SharedPreferences is suitable for this bounded local log; it is not a backup or a multi-device incident-management service.

## Physical test matrix — pending

Automated fixtures are not real-radio certification. Record actual hardware/firmware/build hashes and observations rather than assuming a firmware family is supported.

| Device/build | Status | Required checks |
|---|---|---|
| Seeed T1000-E, 2.7.26.54e0d8d Beta | New candidate not yet tested | Availability/empty TAK and Mesh Beacon, presets/slot zero, explicit retry/cancel, template send/ACK, opt-in GPS, disconnect stop |
| Second radio on a recent supported firmware | Hardware needed | Present/absent module responses, no wrong-section editor, distinct radio attribution, channel selection |
| Firmware returning malformed/empty/no response | Automated fixtures | Empty differs from timeout; mismatched or forged replies cannot open a draft |
| Android gesture/three-button navigation | Device pass needed | Insets on editors and field tools, keyboard, 200% text, light/dark/system theme |
| Background/restart/Bluetooth toggle | Device pass needed | Incident persistence, coverage stays stopped after restart/disconnect, bot budget survives restart, quiet hours, foreground behavior |

Before publishing another beta: complete a fresh T1000-E pass on this exact APK, inspect coverage CSV receiver coordinates and signal/time columns, verify no location broadcasts unless the separate sharing switch is enabled, and confirm failure messages under denied GPS/storage permissions. Additional radios need physical access.
