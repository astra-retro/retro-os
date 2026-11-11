#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 -m py_compile branding/gdm/install-greeter-wallpaper.py
bash -n branding/install-common.sh
python3 - <<'PY'
from pathlib import Path
import configparser
asset=Path("branding/assets/wallpaper-pixel-art.png")
assert asset.stat().st_size > 1024
assert asset.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
common=Path("branding/install-common.sh").read_text()
script=Path("branding/gdm/install-greeter-wallpaper.py").read_text()
assert 'install -m 0644 "$assets/wallpaper-pixel-art.png" /usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png' in common
assert 'test -s /usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png' in common
assert 'python3 "$script_dir/gdm/install-greeter-wallpaper.py"' in common
assert common.index('install -m 0644 "$assets/wallpaper-pixel-art.png"') < common.index("install-greeter-wallpaper.py")
for token in ("gresource", "extract", "glib-compile-resources", "#lockDialogGroup", "background-size: cover", "wallpaper-pixel-art.png", "gnome-shell-theme.gresource"):
    assert token in script, token
assert "glib2-devel" in Path("Containerfile").read_text()
conf=configparser.ConfigParser(interpolation=None)
conf.read("branding/desktop/20-astra-gdm-background")
uri="'file:///usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png'"
assert conf["org/gnome/desktop/background"]["picture-uri"] == uri
assert conf["org/gnome/desktop/background"]["picture-uri-dark"] == uri
assert conf["org/gnome/desktop/screensaver"]["picture-uri"] == uri
assert conf["org/gnome/login-screen"]["logo"] == "''"
PY
echo 'GDM greeter pixel-art wallpaper package checks passed'
