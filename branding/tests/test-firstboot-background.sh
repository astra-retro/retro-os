#!/usr/bin/env bash
# Static sanity checks on Ubuntu; the Fedora OCI build compiles dconf itself.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/install-common.sh
python3 - <<'PY'
import configparser
from pathlib import Path

config = configparser.ConfigParser(interpolation=None)
p = Path('branding/desktop/20-astra-gdm-background')
assert config.read(p, encoding='utf-8') == [str(p)]
expected = "file:///usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png"
background = config['org/gnome/desktop/background']
screensaver = config['org/gnome/desktop/screensaver']
assert background['picture-uri'] == f"'{expected}'"
assert background['picture-uri-dark'] == f"'{expected}'"
assert background['picture-options'] == "'zoom'"
assert screensaver['picture-uri'] == f"'{expected}'"
# The GDM logo is a foreground element; never put a full-size icon here.
# The empty value also clears the problematic setting on upgraded systems.
assert config['org/gnome/login-screen']['logo'] == "''"
assert '512x512/apps/astra-retro-os.png' not in p.read_text()

common = Path('branding/install-common.sh').read_text()
assert 'gdm_profile=/etc/dconf/profile/gdm' in common
assert "grep -qxF 'system-db:gdm'" in common
assert '/etc/dconf/db/gdm.d/20-astra-gdm-background' in common
assert "if [[ \"$mode\" == installed ]]; then" in common
assert common.index('20-astra-gdm-background') < common.index('dconf update')
assert '/usr/share/dconf/profile/gdm' in common
assert 'script_dir/desktop/20-astra-gdm-background' in common
assert 'wallpaper-pixel-art.png' in common
assert 'python3 "$script_dir/gdm/install-greeter-wallpaper.py"' in common
keyboard = Path('branding/desktop/30-astra-gdm-keyboard')
assert config.read(keyboard, encoding='utf-8') == [str(keyboard)]
sources = config['org/gnome/desktop/input-sources']['sources']
assert sources == "[('xkb', 'fr'), ('xkb', 'us')]"
assert config['org/gnome/desktop/input-sources']['xkb-options'] == '@as []'
assert 'locks' not in keyboard.read_text()
assert 'script_dir/desktop/30-astra-gdm-keyboard' in common
assert '/etc/dconf/db/gdm.d/30-astra-gdm-keyboard' in common
assert common.index('30-astra-gdm-keyboard') < common.index('dconf update')

PY
echo "GNOME Initial Setup GDM background checks passed"
