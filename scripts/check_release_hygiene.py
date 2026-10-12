"""Static checks before building a signed artifact."""
import re
import subprocess
from pathlib import Path
tracked = subprocess.check_output(['git', 'ls-files'], text=True).splitlines()
for name in tracked:
    if name.endswith(('.jks', '.keystore', '.p12', '.p8', '.env')) or Path(name).name == 'key.properties':
        raise SystemExit('Tracked signing credential or environment file detected.')
if not re.search(r'^version: \d+\.\d+\.\d+\+\d+$', Path('pubspec.yaml').read_text(), re.M):
    raise SystemExit('Invalid app version/build number.')
print('Release hygiene passed.')
