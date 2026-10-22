# Bastion release readiness — reconciled 2026-10-20

## Implemented on main
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

## Recorded device evidence
The owner reports all six field checks passed on a Seeed T1000-E running Meshtastic
2.7.26.54e0d8d Beta using development APK source 0f81ca9 (app 0.1.2+3), SHA-256
b51af4581411d5f6d62bb66ffaf26daf8e6450e058b8939ae796a12a6ab0098b.
The checks covered settings/presets/channels, themes/large text, incident persistence,
check-in messaging, coverage/CSV/disconnect stop, and bot quiet hours/limits.
This is owner-reported hardware evidence; it is not a pass for a newly signed,
obfuscated artifact or for a second radio. Main PR #49 passed 16 checks and 164 tests.
PR #51 adds fresh same-radio readback for generic editor saves; PR #52 preserves
drafts and the submitted snapshot while verification runs. The published
[v0.1.3-beta.1 release](https://github.com/charlottemeshtastic/Bastion-Meshtastic/releases/tag/v0.1.3-beta.1)
(app 0.1.3+4, source `68abe898`) records owner verification of the exact signed
candidate on the T1000-E and authorization to release. Its
[signed build](https://github.com/charlottemeshtastic/Bastion-Meshtastic/actions/runs/38292447353)
passed 174 app tests. This later evidence supersedes the earlier pending-candidate
status; it does not establish a pass for a second radio or every scenario below. Bulk channel-link imports
now verify with a fresh same-radio readback (see [save verification](SETTINGS-SAVE-VERIFICATION.md)). Backup restore performs its own readback verification.

The [v0.1.2-beta.1 release](https://github.com/charlottemeshtastic/Bastion-Meshtastic/releases/tag/v0.1.2-beta.1) also records owner confirmation that the stable-signed, obfuscated candidate installed, connected, sent a message and retained an incident after restart. Both release records are owner-reported evidence, not independent hardware certification.

## Acceptance gate for the next exact candidate
Work through the [1.0 device test checklist](DEVICE-TEST-CHECKLIST.md) on the exact signed candidate; it covers the items below in order.
- Record commit, APK checksum, signing certificate, Android version, radio model/firmware.
- Install the signed candidate, force-stop and relaunch. Verify QR camera permissions,
  selected secondary-channel delivery, DM, search, backups and wrong-password rejection.
- Restore to the same radio; verify owner, channels, config/modules after reboot.
- Test restore failure/connection loss; do not assume device writes provide rollback.
- Check locked-phone/background, Bluetooth off/on, radio reboot, queued messages on restart.
- Audit merged manifest permissions, startup, APK size and dependency license notices.
- Verify signing-key backup/recovery before public distribution.

## Signing and distribution
A password-protected RSA-3072 signing key was generated with owner approval. A protected local recovery copy exists outside the repository, and the four GitHub encrypted secrets are configured. The owner must make an offline recovery copy. On 2026-10-12 the existing recovery
keystore was decrypted and its private key validated without exposing credentials.
Public certificate/permission policy is pinned in docs/ANDROID-RELEASE-POLICY.json;
the signed workflow verifies the actual APK against it after apksigner verification.
See SIGNING-AND-RECOVERY.md for the transition and recovery procedure.
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
