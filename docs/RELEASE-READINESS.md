# Bastion release readiness — 2026-10-11

## Completed in this change
- Chat channel selector uses enabled radio slots; every send carries the chosen slot.
- Search filters the full retained local history, including queued messages.
- Password-encrypted radio settings backup/restore, with preview, target confirmation,
  fresh reads, firmware-section preflight, reconnect and matching readback.
- Backup encryption: AES-256-GCM; fresh 16-byte salt and 12-byte nonce;
  PBKDF2-HMAC-SHA256 (600,000 iterations). Passwords are not persisted.
- Backup covers owner names, all eight channel slots, advertised config/module sections.
  Device identity/security keys, session credentials, phone history and maps are excluded.
- Release signing configuration refuses missing secrets; manual workflow builds signed
  APK/AAB and archives signature, checksums and symbols. It does not publish to Play.

## User-reported completion, evidence still needed
The owner reported settings readback, physical hardware testing and messaging reliability
as completed on 2026-10-11. No radio models, Android versions, firmware versions,
logs or test matrix were supplied. This statement is not independent verification.
The current main editor still reports success after ACK without automatic readback;
any separately completed implementation must be located and reconciled before claiming it
is included in a release. The new backup restore does its own readback verification.

## Exact candidate acceptance gate
- Record commit, APK checksum, signing certificate, Android version, radio model/firmware.
- Install the signed candidate, force-stop and relaunch. Verify QR camera permissions,
  selected secondary-channel delivery, DM, search, backups and wrong-password rejection.
- Restore to the same radio; verify owner, channels, config/modules after reboot.
- Test restore failure/connection loss; do not assume device writes provide rollback.
- Check locked-phone/background, Bluetooth off/on, radio reboot, queued messages on restart.
- Audit merged manifest permissions, startup, APK size and dependency license notices.
- Verify signing-key backup/recovery before public distribution.

## Signing and distribution
The signing key must stay outside the repository and have an offline recovery copy.
GitHub repository secrets: BASTION_KEYSTORE_BASE64, BASTION_STORE_PASSWORD,
BASTION_KEY_PASSWORD, BASTION_KEY_ALIAS. Only the manually started main-branch signed
candidate workflow uses them. Existing development APKs use a different certificate:
users may need to uninstall first, which removes local data. Export needed data before
uninstalling; the radio-settings backup does not include phone message history.
For Google Play, enroll in Play App Signing and treat this as an upload key. Store
listing, Data Safety and account-side setup remain owner actions.

## Privacy review
BLE discovery/connection uses nearby-device permissions. Opt-in phone GPS is sent to
radio firmware, which can broadcast it onto the mesh. Camera permission supports QR
scanning. Notifications and the foreground service support messaging/background BLE.
Map tile requests go to the configured OpenStreetMap endpoint and disclose IP address
and requested tile coordinates. Radio network/MQTT settings can enable firmware-side
network sharing. Encrypted backup copying is a deliberate clipboard action; clipboard
managers may retain ciphertext. No claim that all data stays on the phone is appropriate.
No analytics or crash-reporting SDK is declared in the direct dependency list; transitive
and merged-manifest checks must be completed on the exact candidate.

## License review
Generated protocol code comes from meshtastic/protobufs v2.8.1. That source distributes
GPL-3.0 license text, preserved under licenses/. The previous README claim that no
upstream generated source is included was incorrect. Corresponding-source, attribution,
application licensing and third-party notices need final review before a production
release; this document is not a legal clearance. The Flutter license page exposes the
notices included by dependencies.
