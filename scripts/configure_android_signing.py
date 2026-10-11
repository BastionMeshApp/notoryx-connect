"""Enable explicit release signing; credentials are supplied only by CI secrets."""
import base64
import os
from pathlib import Path

required = ['BASTION_KEYSTORE_BASE64', 'BASTION_STORE_PASSWORD', 'BASTION_KEY_PASSWORD', 'BASTION_KEY_ALIAS']
if not all(os.environ.get(k) for k in required):
    raise SystemExit('Signing secrets are incomplete; refusing a debug-signed release.')
keystore = Path('android/app/bastion-upload.p12')
keystore.write_bytes(base64.b64decode(os.environ['BASTION_KEYSTORE_BASE64'], validate=True))
keystore.chmod(0o600)
p = Path('android/app/build.gradle.kts')
s = p.read_text()
marker = '    buildTypes {'
if marker not in s or 'signingConfig = signingConfigs.getByName("debug")' not in s:
    raise SystemExit('Unexpected Android template; refusing to guess signing configuration.')
s = s.replace(marker, '''    signingConfigs {
        create("release") {
            storeFile = file("bastion-upload.p12")
            storeType = "PKCS12"
            storePassword = System.getenv("BASTION_STORE_PASSWORD")
            keyPassword = System.getenv("BASTION_KEY_PASSWORD")
            keyAlias = System.getenv("BASTION_KEY_ALIAS")
        }
    }
''' + marker, 1)
s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
p.write_text(s)
print('Release signing configured from protected secrets.')
