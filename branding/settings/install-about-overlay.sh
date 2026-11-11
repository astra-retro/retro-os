#!/usr/bin/env bash
# Remove only GNOME Settings > System > About's donation row.
set -euo pipefail
src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="$(rpm -q --qf '%{VERSION}' gnome-control-center)"
major="${version%%.*}"
case "$major" in
  49|50) source_blp="$src_dir/cc-about-page-49.blp" ;;
  51)    source_blp="$src_dir/cc-about-page-51.blp" ;;
  *) echo "ERROR: Unsupported GNOME Settings version: $version" >&2; exit 1 ;;
esac
command -v blueprint-compiler >/dev/null || { echo "ERROR: blueprint-compiler unavailable" >&2; exit 1; }
target_dir=/usr/share/astra-retro-os/settings-ui
install -d "$target_dir"
blueprint-compiler compile --output "$target_dir/cc-about-page.ui" "$source_blp"
python3 - "$target_dir/cc-about-page.ui" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
path = Path(sys.argv[1])
root = ET.parse(path).getroot()
template = root.find('.//template')
assert template is not None and template.attrib.get('class') == 'CcAboutPage'
assert len(root.findall(".//*[@id='os_logo']")) == 1
text = path.read_text()
assert 'Support GNOME' not in text
assert 'os_name_row' in text
PY
install -D -m 0644 "$src_dir/70-astra-settings-ui.conf" /usr/lib/environment.d/70-astra-settings-ui.conf
echo "Astra Settings About donation row removed for GNOME $version"
