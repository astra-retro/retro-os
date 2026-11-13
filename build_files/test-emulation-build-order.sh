#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash -n build_files/build.sh build_files/05-retro-emulation.sh build_files/06-finalize.sh
python3 - <<'PY'
from pathlib import Path
source = Path('build_files/build.sh').read_text()
assert source.index('/ctx/04-install-packages.sh') < source.index('/ctx/05-retro-emulation.sh') < source.index('/ctx/06-finalize.sh')
assert source.index('/ctx/06-finalize.sh') < source.index('/tmp/system_files/overrides/*')

emulation = Path('build_files/05-retro-emulation.sh').read_text()
assert emulation.index('cp --archive --verbose --force /tmp/system_files/retro-emulation/usr/. /usr/') < emulation.index('for tool in retro-emulation-setup')
assert 'test -s /usr/share/retro-os/esde/splash.svg' in emulation
helper_dir = Path('system_files/retro-emulation/usr/libexec/retro-os')
for name in ('retro-emulation-setup', 'retro-fetch-esde', 'retro-launch-esde', 'retro-install-emudeck', 'retro-configure-esde'):
    path = helper_dir / name
    assert path.is_file() and path.stat().st_size, str(path)
assert Path('system_files/retro-emulation/usr/lib/systemd/user/retro-emulation-setup.service').is_file()
assert Path('system_files/retro-emulation/usr/share/retro-os/esde/splash.svg').is_file()
PY
echo 'Retro emulation install-order checks passed'
