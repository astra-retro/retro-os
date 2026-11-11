#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/install-common.sh branding/settings/install-about-overlay.sh
python3 - <<'PY'
from pathlib import Path
for major in (49, 51):
    template = Path(f"branding/settings/cc-about-page-{major}.blp").read_text()
    assert "template $CcAboutPage: Adw.NavigationPage" in template
    assert "os_logo" in template and "os_name_row" in template
    assert "Support GNOME" not in template and "D_onate" not in template
    assert "on_donate_button_clicked_cb" not in template
installer = Path("branding/settings/install-about-overlay.sh").read_text()
assert "blueprint-compiler compile --output" in installer
assert "49|50)" in installer and "51)" in installer
assert "G_RESOURCE_OVERLAYS" in Path("branding/settings/70-astra-settings-ui.conf").read_text()
assert "blueprint-compiler" in Path("Containerfile").read_text()
assert 'bash "$script_dir/settings/install-about-overlay.sh"' in Path("branding/install-common.sh").read_text()
PY
echo "GNOME Settings donation row checks passed"
