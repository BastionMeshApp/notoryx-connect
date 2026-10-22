# Settings save verification

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
another write.

Bulk channel-link imports (QR, camera or pasted link) follow the same rule in
`BastionChannelImport`: read all 8 slots (and LoRa when replacing) first, write once
in one transaction, wait for the same radio, then compare a fresh read of every
written slot and the LoRa config with `matchesChanges`. An interrupted write, a
reconnect to a different radio, a reconnect timeout or a mismatched slot is reported
as "not verified"; nothing is resent automatically, and the import screen blocks a
second attempt until it is reopened. Refusals before any write (no radio, too few
free slots) say nothing was written.

## Physical acceptance needed

Repeat on every stable-signed candidate, updating the previous stable beta in place.
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

5. Import a channel link with Add and with Replace all; expect "verified from radio"
   only after the reconnect and fresh read.

Editor-save verification first shipped in v0.1.3-beta.1, whose release notes record
owner acceptance of the exact signed candidate on the T1000-E. Each new candidate must
pass these physical save/reboot checks again before release.
