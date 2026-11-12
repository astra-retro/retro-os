#!/usr/bin/env bash
set -euo pipefail

# Run as an ordinary user (the ES-DE helper rejects root).
if (( EUID == 0 )); then
  echo 'SKIP: run ES-DE config tests as a non-root user'
  exit 0
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/system_files/retro-emulation/usr/libexec/retro-os/retro-configure-esde"
splash="$repo_root/system_files/retro-emulation/usr/share/retro-os/esde/splash.svg"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ESDE_APPDATA_DIR="$tmp/ES-DE"
export ASTRA_ESDE_SPLASH_SOURCE="$splash"
settings="$ESDE_APPDATA_DIR/settings/es_settings.xml"

assert_color() {
  python3 - "$settings" "${1:-00FFFFFF}" <<'PY'
import sys
import xml.etree.ElementTree as ET
with open(sys.argv[1], encoding='utf-8') as f:
    data = f.read()
# ES-DE expects a fragment without a <config> root.
assert '<config' not in data
root = ET.fromstring('<root>' + data + '</root>')
values = [e.get('value') for e in root if e.tag == 'string' and
          e.get('name') == 'SplashScreenProgressBarColor']
assert values == [sys.argv[2]], values
PY
}

bash "$helper"
test -s "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"
assert_color
before="$(sha256sum "$settings" | cut -d' ' -f1)"
bash "$helper"
test "$before" = "$(sha256sum "$settings" | cut -d' ' -f1)"

# Migrate the malformed XML produced by the previous Astra installer.
printf '<config>\n<bool name="ShowHiddenGames" value="true" />\n<string name="SplashScreenProgressBarColor" value="79010FFF" />\n</config>\n' > "$settings"
bash "$helper"
assert_color
grep -q ShowHiddenGames "$settings"

# Existing custom colors are never overwritten.
printf '<bool name="ShowHiddenGames" value="false" />\n<string name="SplashScreenProgressBarColor" value="FF00FFFF" />\n' > "$settings"
bash "$helper"
assert_color FF00FFFF
grep -q ShowHiddenGames "$settings"

# Replace ES-DE red default without touching other settings.
printf '<int name="MaxVRAM" value="1024" />\n<string name="SplashScreenProgressBarColor" value="79010FFF" />\n' > "$settings"
bash "$helper"
assert_color
grep -q MaxVRAM "$settings"

# Preserve personalized images.
printf '\n<!-- local edit -->\n' >> "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"
bash "$helper"
grep -q 'local edit' "$ESDE_APPDATA_DIR/resources/graphics/splash.svg"

# Preserve damaged settings instead of overwriting user data.
printf 'broken XML' > "$settings"
bash "$helper"
test "$(cat "$settings")" = 'broken XML'
echo 'ES-DE splash and native cyan settings tests passed'
