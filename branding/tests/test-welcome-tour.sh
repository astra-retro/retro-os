#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/install-common.sh
python3 - <<'PY'
import configparser
from pathlib import Path
p = Path("branding/desktop/26-astra-no-welcome-tour")
config = configparser.ConfigParser(interpolation=None)
assert config.read(p, encoding='utf-8') == [str(p)]
assert config['org/gnome/shell']['welcome-dialog-last-shown-version'] == "'4294967295'"
common = Path("branding/install-common.sh").read_text()
assert 'if [[ "$mode" == installed ]]; then' in common
assert "welcome-dialog-last-shown-version" in common
assert "26-astra-no-welcome-tour" in common
assert common.index("26-astra-no-welcome-tour") < common.index("dconf update")
assert "InitialSetupEnable=false" not in common
assert "gnome.initial-setup=0" not in common
PY
echo "GNOME Welcome Tour first-login defaults: OK"
