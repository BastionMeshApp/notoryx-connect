# Settings save verification — 0.1.3+4 candidate

Owner, LoRa, channel, device, position and generic config/module editors now write
once, wait for the same local radio to be ready, perform a new admin read, and check
only the fields deliberately edited. Protobuf default values compare by meaning,
including omitted Long Fast (zero) and false/disabled values. Unrelated fields
normalized by firmware do not produce a false mismatch.

Only a matching fresh read produces “saved and verified.” A mismatch, read failure,
reconnect timeout or radio switch keeps the editor open. It explains that the radio
may have applied the change and requires a reload before another save; no automatic
repeat write or rollback occurs. Changing radios between load/confirmation/save
blocks the write.

Automated tests cover the comparator, defaults, nested channel key bytes, unrelated
normalization, single-write ordering, identity changes and timeout. Editor tests
check verified success and ACK-without-matching-value, including reload without
another write. This applies to editor saves; bulk channel-link imports retain their
separate transaction flow and need their own readback improvement.

## Physical acceptance needed

Use a stable-signed 0.1.3+4 candidate to update the stable 0.1.2+3 beta in place.
Do not use the automatically generated development-signed APK for that update.

On the T1000-E:
1. Make a harmless owner-name change; confirm success appears only after a fresh read.
2. Reopen the editor and verify the value. Restore the original name if desired.
3. Try an appropriate non-disruptive config/module change supported by your radio;
   verify readback after any reboot/reconnect. Avoid changing region/channel keys
   merely to test this flow.
4. During a save, test a disconnect/failed reconnect. Expect an uncertain-save message,
   no repeat write, and an explicit reload before continuing. Do not assume a failed
   confirmation means the radio rolled back.

The existing v0.1.2-beta.1 release is unchanged. This candidate must pass physical
save/reboot validation before a future release.
