import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/android_smoke_test.sh'
FAKE_ADB = '''#!/usr/bin/env python3
import os
import sys
args = sys.argv[1:]
case = os.environ['BASTION_SMOKE_CASE']
if args[0] == 'install':
    sys.exit(42 if case == 'install_failure' else 0)
if args[:4] == ['shell', 'pm', 'list', 'packages']:
    print('package:org.backcountrysignal.bastion')
elif args[:3] == ['shell', 'am', 'start']:
    print('Status: timeout')
elif args[:2] == ['shell', 'pidof']:
    if case == 'process_gone':
        sys.exit(1)
    print('12345')
elif args[0] == 'logcat' and args[-1] == '-d':
    if any(arg.startswith('--pid=') for arg in args):
        assert '--pid=12345' in args
        print('FATAL EXCEPTION: main' if case == 'crash' else 'App is alive')
    elif case != 'never_displayed':
        print('ActivityTaskManager: Displayed org.backcountrysignal.bastion/.MainActivity: +15s')
elif args[0] == 'exec-out':
    print('screenshot fixture')
'''


class SmokeScriptTest(unittest.TestCase):
    def run_case(self, case, succeeds):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adb = root / 'adb'
            adb.write_text(FAKE_ADB)
            adb.chmod(0o755)
            # Advance the fake startup window without making unit tests sleep.
            sleep = root / 'sleep'
            sleep.write_text('#!/bin/sh\nexit 0\n')
            sleep.chmod(0o755)
            env = dict(os.environ, BASTION_SMOKE_ADB=str(adb),
                       BASTION_SMOKE_CASE=case, BASTION_SMOKE_ATTEMPTS='2',
                       PATH=str(root) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['bash', str(SCRIPT)], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode == 0, succeeds, result.stderr)
            self.assertTrue((root / 'emulator-log.txt').exists())
            self.assertTrue((root / 'emulator-screen.png').exists())

    def test_android_wait_timeout_requires_real_display_and_live_process(self):
        self.run_case('healthy', True)

    def test_live_process_without_a_displayed_activity_fails(self):
        self.run_case('never_displayed', False)

    def test_process_death_after_display_fails(self):
        self.run_case('process_gone', False)

    def test_fatal_exception_fails(self):
        self.run_case('crash', False)

    def test_install_failure_retains_diagnostics(self):
        self.run_case('install_failure', False)


if __name__ == '__main__':
    unittest.main()
