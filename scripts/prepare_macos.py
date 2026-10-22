"""Run after `flutter create --platforms=macos .` to brand the app and add the
permissions NOTORYX Connect needs on macOS (Bluetooth, network, camera,
location, user-chosen files). Idempotent."""
import plistlib
import re
from pathlib import Path

RUNNER = Path('macos/Runner')

config = RUNNER / 'Configs/AppInfo.xcconfig'
text = config.read_text()
text = re.sub(r'^PRODUCT_NAME = .*$', 'PRODUCT_NAME = NOTORYX Connect', text, flags=re.M)
text = re.sub(r'^PRODUCT_COPYRIGHT = .*$',
              'PRODUCT_COPYRIGHT = NOTORYX Connect. Meshtastic® is a registered trademark of Meshtastic LLC.',
              text, flags=re.M)
config.write_text(text)


def update(path, values):
    with path.open('rb') as f:
        plist = plistlib.load(f)
    plist.update(values)
    with path.open('wb') as f:
        plistlib.dump(plist, f)


update(RUNNER / 'Info.plist', {
    'CFBundleDisplayName': 'NOTORYX Connect',
    'NSBluetoothAlwaysUsageDescription':
        'NOTORYX Connect uses Bluetooth to connect to your LoRa mesh radio.',
    'NSCameraUsageDescription':
        'NOTORYX Connect uses the camera only to scan channel QR codes you choose to scan.',
    'NSLocationUsageDescription':
        'NOTORYX Connect uses your location only if you turn on location sharing or coverage recording.',
    'NSLocationWhenInUseUsageDescription':
        'NOTORYX Connect uses your location only if you turn on location sharing or coverage recording.',
    # Impeller scrambles text on some Intel Mac GPUs; use the Skia renderer.
    'FLTEnableImpeller': False,
})

entitlements = {
    'com.apple.security.app-sandbox': True,
    'com.apple.security.device.bluetooth': True,
    'com.apple.security.network.client': True,
    'com.apple.security.device.camera': True,
    'com.apple.security.personal-information.location': True,
    'com.apple.security.files.user-selected.read-write': True,
}
for name in ('DebugProfile.entitlements', 'Release.entitlements'):
    update(RUNNER / name, entitlements)
print('Prepared macOS app name, permissions and entitlements')
