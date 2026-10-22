# Google Play submission guide — NOTORYX Connect 1.0.0

Everything needed in Play Console, with recommended answers. Recommended answers are drafted from the 1.0.0 code; re-check them if features change. Items marked **Owner** need the account holder.

## 1. Before the first upload (Owner)
- [ ] Play Console developer account, identity verification, and (for a new personal account) the closed-testing requirement Google currently applies before production.
- [ ] Create the app: name **NOTORYX Connect**, default language English (US), App, Free.
- [ ] Enroll in **Play App Signing**. Upload the AAB from the `NOTORYX Signed Release Candidate` workflow; its key becomes the **upload key** (see [signing and recovery](SIGNING-AND-RECOVERY.md)). Package `org.backcountrysignal.bastion` is permanent once uploaded.
- [ ] Fill in the placeholders in [PRIVACY-POLICY.md](PRIVACY-POLICY.md) (`[DATE…]`, `[PUBLISHER NAME]`, `[CONTACT EMAIL]`) and publish it at a stable public URL. A GitHub link to the file on `main` works; a page on your own site is better.
- [ ] Trademark/domain clearance for "NOTORYX" (issue #55), and a re-check of the current [Meshtastic trademark rules](https://meshtastic.org/docs/legal/licensing-and-trademark/) ([TRADEMARKS.md](../TRADEMARKS.md) rule 8).

## 2. Store listing
Text is in `fastlane/metadata/android/en-US/` (title 15/30, short 73/80, full description about 2,000/4,000 characters, release notes for version code 5).

Graphics (made from the approved NOTORYX artwork in `branding/notoryx-icon-source.png`; regenerate with `tool/make_store_graphics.py`):
- [x] App icon, 512 × 512 PNG: `fastlane/metadata/android/en-US/images/icon.png`
- [x] Feature graphic, 1024 × 500: `fastlane/metadata/android/en-US/images/featureGraphic.png`
- [ ] 2–8 phone screenshots (**Owner**) (16:9 or 9:16, at least 320 px on the short side). Suggested: Nodes with a connected radio, Chats, Map with nodes, Field tools, Settings → Field alerts, Privacy & data. Don't show real names, locations or channel keys.

Category: **Communication**. Tags: messaging, outdoors/navigation. Contact email: the support address you choose (public).

## 3. App content

### Privacy policy
The URL from step 1.

### Ads
**No**, the app contains no ads.

### App access
**All functionality is available without special access** (no login). Add this note for reviewers:
> Most features need a LoRa radio running Meshtastic firmware connected over Bluetooth. Without one, reviewers can explore every tab, Settings (including Privacy & data, Field alerts, backups) and Field tools; the Nodes tab shows how to connect a radio.

### Content rating (IARC questionnaire)
Category **Communication** (or "All other app types"). Key answers:
- Users can interact or exchange content (messages): **Yes**. Messages are not moderated; they travel over a peer-to-peer radio mesh.
- Shares the user's physical location with other users: **Yes**, opt-in (phone location sharing).
- Violence, sexual content, profanity, drugs, gambling: **No** (beyond unmoderated user messages).
- Digital purchases: **No**.

### Target audience
**13+** (or 18+). Not designed for children; no child-directed content.

### News app / COVID / government / financial features
**No** to each.

### Foreground service declaration (required)
Permission `FOREGROUND_SERVICE_CONNECTED_DEVICE`, type **Connected device**.
- **Use:** keeps the Bluetooth connection to the user's LoRa radio open while the app is in the background, so incoming mesh messages and alerts are received. Started only while a radio is connected, stopped on disconnect, shown as an ongoing notification.
- **Video (Owner):** a short screen recording showing: connect a radio, the "Connected to …" notification appears, switch to the home screen, a message arrives, disconnect and the notification disappears.

### Location permission
Foreground location only; **no background location** is requested, so no background-location declaration is needed.

### Data Safety form
Google counts data as **collected** when the app transmits it off the device, even with no developer server. NOTORYX Connect sends some data to *other mesh users* and *map tile servers*, so the conservative, recommended answers are below. Reasons are given so you can adjust them if Google's guidance changes.

**Does your app collect or share any of the required user data types?** **Yes.**

**Is all of the user data collected by your app encrypted in transit?** **No.** Mesh messages use the channel key, but default channel keys are public and positions can be sent on them, so "encrypted in transit" can't be promised for everything.

**Do you provide a way for users to request that their data is deleted?** **Yes**: Settings → Privacy & data deletes all locally stored data. The developer holds no copy.

| Data type | Collected | Shared | Optional? | Purpose | Notes |
|---|---|---|---|---|---|
| Location → **Approximate location** | Yes | Yes | **Optional** (off by default) | App functionality | Sent to the user's radio and broadcast to mesh users only when "Share phone location" is on; can be rounded to about 360 m / 1.5 km / 6 km |
| Location → **Precise location** | Yes | Yes | **Optional** | App functionality | Same feature, when precision is set to Precise |
| Messages → **Other in-app messages** | Yes | Yes | Required for messaging | App functionality | Sent to the user's own radio and on to mesh recipients at the user's request; never to the developer |
| Device or other IDs | No | No | | | The radio's node ID is the radio's, not the phone's |
| App activity, app info and performance, personal info, financial, health, photos, files, contacts, calendar, web history | No | No | | | Nothing else leaves the device; backups are user-exported, encrypted files |

"Shared" means transferred to a third party: other mesh users receive messages and opted-in location. Data is **not** processed ephemerally, sold, or used for ads or analytics.

Map tiles: the app requests tiles from OpenStreetMap, which sees the phone's IP address. Play does not list IP address as its own type; this is disclosed in the privacy policy.

## 4. Release
- Version **1.0.0 (5)**. Build it with the `NOTORYX Signed Release Candidate` workflow from `main` and run the acceptance checklist in [release readiness](RELEASE-READINESS.md) on that exact AAB/APK first.
- Start with an **internal or closed testing** track, then production.
- After upload: Play Console → App integrity, and confirm the app-signing certificate. The upload certificate must match `docs/ANDROID-RELEASE-POLICY.json`.
