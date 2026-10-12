# Bastion release readiness — 2026-10-12

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

## Recorded device evidence
The owner reports all six field checks passed on a Seeed T1000-E running Meshtastic
2.7.26.54e0d8d Beta using development APK source 0f81ca9 (app 0.1.2+3), SHA-256
b51af4581411d5f6d62bb66ffaf26daf8e6450e058b8939ae796a12a6ab0098b.
The checks covered settings/presets/channels, themes/large text, incident persistence,
check-in messaging, coverage/CSV/disconnect stop, and bot quiet hours/limits.
This is owner-reported hardware evidence; it is not a pass for a newly signed,
obfuscated artifact or for a second radio. Main PR #49 passed 16 checks and 164 tests.
The generic main editor still reports success after ACK without automatic readback;
backup restore performs its own readback verification.

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
