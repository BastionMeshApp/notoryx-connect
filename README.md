# NOTORYX Connect

> **NOTORYX rebrand in progress:** This project is transitioning to **NOTORYX Connect**, part of the **NOTORYX** off-grid communications family. **No Towers. No Limits.** Existing releases, package identifiers and documentation may still use Bastion until migration is tested. This project remains independent of the underlying radio protocol projects.

**No Towers. No Limits.**

**NOTORYX Connect** is an independent Android field-mesh application. It interoperates with devices running Meshtastic® firmware while maintaining its own name, icon, interface, and project identity.

> **Independent project:** Bastion is not affiliated with, sponsored by, endorsed by, or an official application of Meshtastic LLC.

## Development status

Bastion is under active development. BLE transport, PhoneAPI synchronization, NodeDB, channel/direct messaging, offline queueing, and field tooling are being developed and tested. Do not rely on a development build as the sole method of emergency communication.

## Mission

NOTORYX Connect is designed for backcountry users, community mesh networks, radio enthusiasts, preparedness, field deployments, and emergency-communications support. The project emphasizes reliable offline operation, field-friendly controls, radio diagnostics, network visibility, privacy-conscious operation, and useful automation.

## Interface

NOTORYX Connect uses its own black/charcoal field-oriented identity with restrained signal accents. Primary navigation is:

- **NODES** — discovered radios, nodes, status, telemetry, signal information, and network intelligence
- **CHATS** — direct and channel communications
- **MAP** — node locations, field information, coverage, and offline mapping
- **TOOLS** — diagnostics, traceroute, radio, and field utilities
- **SETTINGS** — application, connection, radio, privacy, appearance, and legal notices

## Compatibility

NOTORYX Connect implements interoperability with the public protocol used by Meshtastic® firmware. Technical references to Meshtastic® in source code and documentation describe compatibility or protocol behavior; they are not Bastion product branding.

NOTORYX Connect does not use “Meshtastic” in its primary or secondary software product name. The official Meshtastic logo is not used as the NOTORYX Connect application icon or primary branding.

## Trademark and licensing notice

Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic software components are released under various licenses, see GitHub for details. No warranty is provided - use at your own risk.

NOTORYX Connect is independently developed and is not affiliated with, sponsored by, or endorsed by Meshtastic LLC. All Meshtastic® trademarks remain the property of Meshtastic LLC.

Official policy and project information:

- Licensing and trademark rules: https://meshtastic.org/docs/legal/licensing-and-trademark/
- Official website: https://meshtastic.org/
- Official GitHub organization: https://github.com/meshtastic

See [TRADEMARKS.md](TRADEMARKS.md) for NOTORYX Connect's trademark-use rules.

## Upstream software and third-party licenses

Meshtastic software components are released under various licenses. NOTORYX Connect must preserve all applicable license notices, attribution, source-distribution obligations, and other requirements for any upstream component that is actually incorporated into the project.

NOTORYX Connect includes generated protocol bindings from `meshtastic/protobufs` v2.8.1. Its GPL-3.0 license text is preserved in `licenses/meshtastic-protobufs-GPL-3.0.txt`. NOTORYX Connect is licensed under GPL-3.0; see [LICENSE](LICENSE). Keep the generated-code and third-party notices with distributed builds. See [release readiness](docs/RELEASE-READINESS.md) for the remaining release checks.

Third-party Flutter/Dart dependencies remain subject to their respective licenses.

## Android application

NOTORYX Connect's Android display name is **NOTORYX Connect**. CI generates the Android project using the Dart project name `bastion` and organization `org.backcountrysignal`.

The NOTORYX Connect application icon is located at:

```text
branding/bastion-icon.png
```

The icon and NOTORYX Connect visual identity are independent artwork and must not incorporate the official Meshtastic logo unless a future use is separately authorized and complies with the then-current trademark rules.

## Local development

Requirements:

- Flutter 3.47.7
- Java 17
- Android SDK

After cloning this repository:

```sh
flutter create --no-pub --platforms=android --org org.backcountrysignal --project-name bastion .
git checkout -- pubspec.lock   # flutter create replaces it with a template
python3 scripts/prepare_android.py
flutter pub get --enforce-lockfile
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter run
```

Dependency versions are locked in the committed `pubspec.lock`, and CI runs `flutter pub get --enforce-lockfile`, so every build uses the same packages. To change a dependency, edit `pubspec.yaml`, run plain `flutter pub get`, and commit the updated `pubspec.lock`.

## Build validation

Pull requests and pushes are validated by the Android CI workflow with Flutter analysis, tests, an ARM64 release APK build, and a retained APK artifact.

A build should not be represented as production-ready until hardware testing, release signing, dependency/license review, privacy review, and release QA are complete.

## Safety

NOTORYX Connect may support field and emergency-communications workflows, but software and mesh radio links are not guaranteed emergency lifelines. Maintain appropriate backup communications and safety plans for the environment in which Bastion is used.

## Contributing

Testing, bug reports, hardware compatibility reports, and feature ideas are welcome. Contributions must preserve NOTORYX Connect's independent branding and comply with [TRADEMARKS.md](TRADEMARKS.md) and all applicable third-party licenses.

## Current completion and release gates

See [release readiness](docs/RELEASE-READINESS.md) and [branch/PR triage](docs/BRANCH-AND-PR-TRIAGE.md). Encrypted radio backup/restore excludes device identity keys, session credentials and phone history; the separate encrypted phone data backup covers chats, offline queues, NodeDex, waypoints, field records and settings. Signed candidates are built through the manual main-branch workflow; they are not automatically published.
