# NOTORYX Connect 1.0 device test checklist

One pass through the app on real hardware before releasing 1.0.0. Work top to bottom; later steps build on earlier ones. It takes about an hour with one radio, plus about 30 minutes for the two-radio steps (marked **2 radios**).

Tick each box when it behaves as described. If something doesn't, note what happened in the **Notes** column at the end and keep going.

**You need:** the signed 1.0.0 APK from the `Bastion Signed Release Candidate` workflow (not a development build), your phone, radio A, and if possible radio B and a second phone with the app. Use a test channel, not one other people rely on.

## 0. Record what you're testing
- [ ] Commit: `________`  APK SHA-256 (from `SHA256SUMS.txt`): `________`
- [ ] Phone model and Android version: `________`
- [ ] Radio A model and firmware: `________`  Radio B: `________`

## 1. Install and update
- [ ] **Update in place** over the current stable-signed beta (don't uninstall). The app opens, and old chats and settings are still there.
- [ ] The launcher and app bar say **NOTORYX Connect**; Settings → About says NOTORYX Connect, version 1.0.0.
- [ ] Force-stop the app (Android Settings → Apps), reopen: no crash, data still there.

## 2. Connect radio A
- [ ] Nodes tab → scan → **CONNECT** to radio A. Status goes through connecting/synchronizing to ready; the node list fills in.
- [ ] Turn phone Bluetooth off: the app says it will reconnect. Turn it on: it reconnects by itself.
- [ ] Reboot radio A: the app reconnects by itself once the radio is back.

## 3. Messaging
- [ ] Send a channel message: it shows sent, and another radio or app receives it.
- [ ] Send a DM to another node: delivery status updates.
- [ ] **Offline queue:** disconnect, send a message (shows QUEUED), force-stop and reopen the app (still QUEUED), reconnect: it sends.
- [ ] Bot (optional): turn it on, send `!help` from another node, get one `NOTORYX:` reply.

## 4. History per radio (2 radios)
- [ ] With radio A connected, note a few messages and favorite one node.
- [ ] Connect radio B: Chats shows only B's history and the node list only what B heard. The favorite star still appears if B hears that node.
- [ ] Queue a message while connected to nothing, then connect B: it does **not** send through B. Reconnect A: it sends through A.
- [ ] Reconnect A: A's history is all back.

## 5. Radio settings and channels
- [ ] Settings → Change radio settings → edit the owner short name and save: success appears only after the read-back. Change it back.
- [ ] Channels → share: a QR code and link appear.
- [ ] On a second phone (or after a radio backup), **Import → Add to radio** from that QR/link: "written and verified from radio".
- [ ] **Replace all** (on a test radio only, with a radio backup first): the radio reboots, the app reconnects, then reports verified.

## 6. Field alerts and location
- [ ] Settings → Field alerts: the defaults are low battery on and the other two off.
- [ ] Favorite a node, turn on **Favorite goes quiet**, set it to 30 min, switch that node off: exactly **one** notification after about 30 minutes.
- [ ] Turn on **New node**; when a node your radio has never heard appears, you get one notification.
- [ ] Settings → Share phone location on; on another node, your position appears.
- [ ] Set **Location precision** to about 1.5 km: other nodes show you at a rounded position, not your exact spot.
- [ ] Turn on Low-power field mode: sharing keeps working, with less frequent updates.

## 7. Background
- [ ] With the radio connected, lock the phone for 15+ minutes: the "Connected to …" notification stays, and a message sent to you arrives as a notification.
- [ ] Disconnect in the app: the background notification goes away.

## 8. Backups
- [ ] **Radio backup:** create one, then restore it to the same radio; it reports the read-back matches. A wrong password is refused.
- [ ] **Phone backup:** Settings → Phone data backup → create a file and save it to Files or Drive.
- [ ] Restore it (ideally on the second phone): the preview shows the right counts, the app closes, and after reopening chats, favorites, waypoints and settings are all there. A wrong password is refused.

## 9. Privacy (do this last)
- [ ] Settings → Privacy & data shows what's stored and sent.
- [ ] While connected, **Delete chat history** is refused (disconnect first).
- [ ] Disconnect → Delete chat history → the app closes; on reopening, chats are empty and favorites and settings remain.
- [ ] (Optional, on a test phone) **Delete all phone data** → after reopening, the app is like a fresh install. Restore your phone backup if needed.

## 10. Accessibility and layout
- [ ] Android font size at maximum: every tab is readable with nothing cut off.
- [ ] Light and dark theme, and both gesture and 3-button navigation: nothing hidden behind the system bars.

## Results
| Section | Pass / fail | Notes |
|---|---|---|
| 1 Install | | |
| 2 Connect | | |
| 3 Messaging | | |
| 4 Per radio | | |
| 5 Settings | | |
| 6 Alerts and location | | |
| 7 Background | | |
| 8 Backups | | |
| 9 Privacy | | |
| 10 Layout | | |

Tester: `________`  Date: `________`

Paste the results into the release notes or an issue. A failure in sections 1–3 or 8 should block the release; anything else can be judged case by case.
