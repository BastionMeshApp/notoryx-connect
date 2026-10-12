# Stable Android signing and recovery

Future direct-install APKs must use the existing persistent certificate in
ANDROID-RELEASE-POLICY.json. The signed workflow uses four GitHub encrypted secrets,
verifies APK/AAB signatures, checks package/version/merged permissions/certificate,
and archives per-build symbols. Missing credentials, an unexpected Android template,
a changed certificate, a debuggable APK or a changed permission set block release.
The certificate is public; the private keystore and passwords must never enter Git,
a public release or logs.

## Recovery copy

Keep the original protected PKCS12 keystore on an encrypted offline drive, and keep
its store password, key password and alias in a password manager. The existing local
recovery folder contains the keystore and credentials; protect the whole folder during
transport, then store credentials separately. Keep a second protected copy at another
location. This chat verified that the local keystore decrypts and its private key is
valid; it cannot certify that the owner has made an offline copy.

To recover CI access, restore these repository secrets from that existing key:
BASTION_KEYSTORE_BASE64 (base64 of the PKCS12), BASTION_STORE_PASSWORD,
BASTION_KEY_PASSWORD and BASTION_KEY_ALIAS. Use gh secret set with protected files or
standard input rather than passwords in command arguments/history. Build a manual
signed candidate and verify its certificate matches ANDROID-RELEASE-POLICY.json.
Do not generate a replacement key: Android treats it as a different signer and will
reject updates. A genuinely lost direct-install app-signing key cannot be recreated
from an APK or public certificate. For a future Play launch, use Play App Signing
with a separate upload-key strategy; store-side setup is not completed here.

## One-time transition from development APKs

Older test APKs use temporary debug certificates. A persistent certificate cannot
transparently update those installations. Keep the existing app if Android rejects
an update. Before any uninstall, save radio settings backups and copy incident/coverage
CSV outside the app. Radio backups exclude phone chats, field logs and maps; there is
no complete phone-state export/import in the current build. Do not promise lossless
migration from a debug-signed installation. A spare phone can test the signed candidate
without removing the current installation.

After the first stable-signed installation, later APKs with the same package,
certificate and increasing versionCode can update in place. Verify this path on real
hardware before each release; do not instruct users to uninstall routinely.

## Release acceptance

The owner tested the previous development-signed 0.1.2+3 APK on the T1000-E. The newly
signed and obfuscated candidate must be installed and exercised before its GitHub draft
is published. Record source hash, APK checksum, certificate, device/firmware, startup,
radio connection, messaging and saved field-record behavior after force-stop/relaunch.
Attach the exact tested artifact and its symbols; do not rebuild after acceptance.
