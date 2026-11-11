#!/usr/bin/env bash
# CI assertions for the shared Live + installed Dash to Dock configuration.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/install-common.sh branding/install-live.sh
python3 - <<'PY'
from pathlib import Path
import configparser

dock = Path("branding/desktop/25-astra-dock")
config = configparser.ConfigParser(interpolation=None)
config.read(dock, encoding="utf-8")
assert "dash-to-dock@micxgx.gmail.com" in config["org/gnome/shell"]["enabled-extensions"]
assert "background-logo@fedorahosted.org" in config["org/gnome/shell"]["enabled-extensions"]
section = config["org/gnome/shell/extensions/dash-to-dock"]
assert section["dock-position"] == "'BOTTOM'"
assert section["dock-fixed"] == "true"
assert section["autohide"] == "false"
assert section["intellihide"] == "false"
assert section["show-show-apps-button"] == "true"

common = Path("branding/install-common.sh").read_text()
live = Path("branding/install-live.sh").read_text()
installed = Path("Containerfile").read_text()
installer = Path("installer/build.sh").read_text()

assert 'gnome-shell-extension-dash-to-dock' in installed
assert 'gnome-shell-extension-dash-to-dock' in installer
assert '"$script_dir/desktop/25-astra-dock"' in common
assert common.index('25-astra-dock') < common.index('dconf update')
assert 'gnome-shell/extensions/dash-to-dock@micxgx.gmail.com' in common
# Live may only override installer favorites; its dock is shared.
assert '30-astra-live' in live
assert "favorite-apps=['astra-retro-install.desktop'" in live
assert 'dock-fixed=' not in live
assert 'autohide=' not in live
assert 'enabled-extensions=' not in live
# No Anaconda favorites should be configured in the shared dock defaults.
assert 'astra-retro-install.desktop' not in dock.read_text()
PY
echo 'Shared GNOME dock defaults: OK'
