#!/usr/bin/env bash
set -euo pipefail

# Run as an ordinary user (the ES-DE helper intentionally rejects root).
if (( EUID == 0 )); then
  echo 'SKIP: run this user configuration test without root privileges'
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/system_files/retro-emulation/usr/libexec/retro-os/retro-configure-esde"
splash="$repo_root/system_files/retro-emulation/usr/share/retro-os/esde/splash.svg"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export ESDE_APPDATA_DIR="$tmp/ES-DE"
export ASTRA_ESDE_SPLASH_SOURCE="$splash"
bash "$helper"
test -s "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"
python3 - "$ESDE_APPDATA_DIR/settings/es_settings.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
assert root.tag == 'config'
values = [x.get('value') for x in root.findall('string') if x.get('name') == 'SplashScreenProgressBarColor']
assert values == ['00FFFFFF'], values
PY
# Repeated launches must not duplicate the setting or rewrite a managed splash.
bash "$helper"
[[ "$(grep -c 'SplashScreenProgressBarColor' "$ESDE_APPDATA_DIR/settings/es_settings.xml")" == 1 ]]

# Local modifications are owned by the user, not the image updater.
printf '\n<!-- local edit -->\n' >> "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"
bash "$helper"
grep -q 'local edit' "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"

# Preserve explicit user color preferences.
sed -i 's/00FFFFFF/FF00FFFF/' "$ESDE_APPDATA_DIR/settings/es_settings.xml"
bash "$helper"
grep -q 'FF00FFFF' "$ESDE_APPDATA_DIR/settings/es_settings.xml"
echo 'ES-DE splash and per-user configuration tests passed'
