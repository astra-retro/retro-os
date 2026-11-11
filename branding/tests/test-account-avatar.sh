#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import ast
from pathlib import Path
import re
source = Path("branding/accounts/install-default-avatar.py").read_text()
updater = Path("branding/accounts/apply-generated-avatar.py").read_text()
ast.parse(source)
ast.parse(updater)
assert 'rsvg-convert' in source and "scale(0.72)" in source
assert 'accountsservice/user-templates' in source
assert '"standard", "administrator"' in source
assert 'gnome-generated' in updater and 'SetIconFile' in updater
assert 'current != str(icon)' in updater
assert '60000' in updater
common = Path('branding/install-common.sh').read_text()
assert 'python3 "$script_dir/accounts/install-default-avatar.py" "$assets/astra-retro-os-logo.svg"' in common
assert 'systemctl enable astra-default-avatar.timer' in common
assert common.index('install-default-avatar.py') > common.index('if [[ "$mode" == installed ]]; then')
assert 'librsvg2-tools' in Path('Containerfile').read_text()
timer = Path('branding/systemd/astra-default-avatar.timer').read_text()
assert 'OnUnitActiveSec=60s' in timer
assert 'WantedBy=timers.target' in timer
service = Path('branding/systemd/astra-default-avatar.service').read_text()
assert 'ExecStart=/usr/libexec/astra-retro-os/apply-generated-avatar' in service
PY
echo 'GNOME AccountsService default avatar checks passed'
