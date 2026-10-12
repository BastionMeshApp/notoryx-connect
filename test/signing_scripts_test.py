"""Release-signing preparation refuses incomplete secrets and unexpected templates."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/configure_android_signing.py'

class SigningPreparationTest(unittest.TestCase):
    def run_script(self, root, secrets):
        env = {k: v for k, v in os.environ.items() if not k.startswith('BASTION_')}
        env.update(secrets)
        return subprocess.run(['python3', str(SCRIPT)], cwd=root, env=env, capture_output=True, text=True)

    def test_missing_credentials_does_not_write_files(self):
        with tempfile.TemporaryDirectory() as root:
            result = self.run_script(root, {})
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((Path(root) / 'android').exists())

    def test_explicit_release_config_and_no_passwords_in_gradle(self):
        with tempfile.TemporaryDirectory() as root:
            app = Path(root) / 'android/app'
            app.mkdir(parents=True)
            gradle = app / 'build.gradle.kts'
            gradle.write_text('android {\n    buildTypes {\n        release {\n            signingConfig = signingConfigs.getByName("debug")\n        }\n    }\n}')
            # Fixture bytes only: this checks configuration, not a certificate.
            result = self.run_script(root, {
                'BASTION_KEYSTORE_BASE64': base64.b64encode(b'fixture').decode(),
                'BASTION_STORE_PASSWORD': 'fixture-store-value',
                'BASTION_KEY_PASSWORD': 'fixture-key-value',
                'BASTION_KEY_ALIAS': 'fixture-alias',
            })
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('getByName("debug")', gradle.read_text())
            self.assertIn('getByName("release")', gradle.read_text())
            self.assertNotIn('fixture-store-value', gradle.read_text())
            self.assertEqual((app / 'bastion-upload.p12').stat().st_mode & 0o777, 0o600)

if __name__ == '__main__':
    unittest.main()
