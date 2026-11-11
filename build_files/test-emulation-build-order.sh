#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n build_files/build.sh build_files/05-retro-emulation.sh build_files/06-finalize.sh
python3 - <<'PY'
from pathlib import Path
source = Path('build_files/build.sh').read_text()
setup = source.index('/ctx/05-retro-emulation.sh')
finalize = source.index('/ctx/06-finalize.sh')
copy = source.index('cp --archive --verbose --force /tmp/system_files/usr/. /usr/')
assert source.index('/ctx/04-install-packages.sh') < copy < setup < finalize
assert 'cp --archive --verbose --force \\\n    /tmp/system_files/overrides/*' in source
helper_dir = Path('system_files/usr/libexec/retro-os')
for name in ('retro-emulation-setup','retro-fetch-esde','retro-launch-esde','retro-install-emudeck'):
    path = helper_dir / name
    assert path.is_file() and path.stat().st_size, str(path)
assert Path('system_files/usr/lib/systemd/user/retro-emulation-setup.service').is_file()
PY
echo 'Retro emulation install-order checks passed'
