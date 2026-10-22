# NOTORYX Connect privacy policy

_Effective: [DATE OF FIRST PUBLIC RELEASE]_

NOTORYX Connect ("the app") is an independent Android app for talking to LoRa mesh radios that run Meshtastic® firmware. It is published by [PUBLISHER NAME]. This policy explains what the app stores, what it sends, and the choices you have.

## The short version
- There is **no account**, **no analytics**, **no advertising**, and **no server** run by us. We do not receive, collect or sell any of your data.
- What the app keeps stays in its private storage on your phone.
- The app only sends data off your phone when you use a feature that needs to: messaging through your radio, sharing your location if you turn that on, and loading map images.

## What is stored on your phone
Stored in the app's private storage, which other apps cannot read. Uninstalling the app deletes it.
- Chat history and queued outgoing messages, kept separately for each radio (the newest 500 messages per radio).
- NodeDex: the mesh nodes your radios have heard, with any favorites and notes you add.
- Waypoints received from the mesh.
- Incident log entries and coverage records, only if you create them.
- App settings (alerts, bot replies, location sharing, appearance).
- Map images for areas you have viewed, kept so the map works offline.

## What leaves your phone, and where it goes
- **Messages you send** go over Bluetooth to your own radio, which transmits them on the mesh. Anyone with the same channel key can read them, and on public default channels that key is widely known. Mesh radio is not a secure or guaranteed delivery channel.
- **Your phone's location** is sent to your radio **only if you turn on "Share phone location"**. Your radio then broadcasts it to the mesh. You can choose to round it to about 360 m, 1.5 km or 6 km on your phone before it is sent. It is off by default.
- **Requests you start** (position, telemetry, traceroute, Store & Forward history) are sent through your radio to other nodes.
- **Map images** are downloaded from OpenStreetMap's tile servers when you view the map. Like any website, those servers see your IP address and the map area requested. See the [OpenStreetMap Foundation privacy policy](https://osmfoundation.org/wiki/Privacy_Policy).
- **Backups** you create are encrypted with your password and saved wherever you choose (for example Files or Drive). We never receive them.

## Permissions
- **Bluetooth (nearby devices):** to find and connect to your radio. The scan does not determine your location.
- **Location:** only for sharing your phone's location with the mesh and recording coverage, both off unless you turn them on.
- **Camera:** only to scan channel QR codes when you choose to.
- **Notifications and foreground service:** to keep the radio connection open in the background and to show message and field alerts.
- **Internet:** only to download map images.

## Your choices
- Turn location sharing off at any time, or choose an approximate precision (Settings).
- Delete chat history, or all data the app stores, in **Settings → Privacy & data**. Uninstalling the app also deletes everything.
- Field alerts and bot replies are off or adjustable in Settings.

## Children
The app is not directed at children under 13.

## Changes
If this policy changes, the new version will be published at this address with a new effective date.

## Contact
[CONTACT EMAIL]

Meshtastic® is a registered trademark of Meshtastic LLC. NOTORYX Connect is independently developed and is not affiliated with, sponsored by, or endorsed by Meshtastic LLC.
