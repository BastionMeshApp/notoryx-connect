Bastion’s chat composer was fixed to Channel 0 and its backup codec had no usable encrypted restore flow. This change adds enabled-channel selection, search across retained messages, and password-encrypted radio settings backup/restore with preflight, explicit replacement confirmation, reconnect and fresh readback verification.

AES-256-GCM protects the backup, with PBKDF2-HMAC-SHA256 at 600,000 iterations. Device identity/security keys, session credentials and phone history are excluded. Restore failures do not claim success or promise device-side rollback.

Prepares manual main-only signed APK/AAB builds with signature verification and archived symbols, increments version to 0.1.1+2, preserves the upstream protobuf license, corrects stale documentation, and brings forward previously successful integration dependency/workflow updates. Signing material is kept outside Git in protected local files and GitHub encrypted secrets.

Validation: regression tests cover encrypted roundtrip/tampering/wrong passwords, snapshot validation, unsupported-target refusal before writes, restore sequencing/readback mismatch, chat search and secondary-channel sends. Android CI analysis, tests and APK build are being checked before marking this ready.

Hardware completion was reported by the owner; device versions/logs were not supplied, and main still lacks automatic readback for ordinary settings saves. Exact signed-artifact hardware QA, final licensing/privacy review and Play enrollment are documented release gates. No Play publication or production readiness is claimed.
