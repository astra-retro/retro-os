#!/usr/bin/env bash
# Anaconda branding for the Astra Retro OS Live environment (Fedora 45).
# Supports both classic GTK Anaconda and the PatternFly/Cockpit WebUI.
# ASTRA_ROOT is only intended for tests against a temporary filesystem.
set -euo pipefail

root="${ASTRA_ROOT:-}"
root="${root%/}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_logo="$root/usr/share/icons/hicolor/512x512/apps/astra-retro-os.png"
[[ -s "$source_logo" ]] || { echo "ERROR: Astra Anaconda logo missing: $source_logo" >&2; exit 1; }

installed=0
# GTK: Anaconda reads custom_stylesheet from /etc/anaconda/conf.d/.
# Keep the Fedora/vendor CSS and overlay only the relevant selectors.
if [[ -f "$root/usr/share/anaconda/anaconda-gtk.css" ]]; then
    gtk_dir="$root/usr/share/anaconda/pixmaps"
    conf_dir="$root/etc/anaconda/conf.d"
    install -d "$gtk_dir" "$conf_dir"
    install -m 0644 "$source_logo" "$gtk_dir/astra-anaconda-logo.png"
    install -m 0644 "$script_dir/anaconda-gtk.css" "$gtk_dir/astra-anaconda.css"
    cat > "$conf_dir/999-astra-retro-os-branding.conf" <<'CONF'
[User Interface]
custom_stylesheet = /usr/share/anaconda/pixmaps/astra-anaconda.css
CONF
    grep -q '^custom_stylesheet = /usr/share/anaconda/pixmaps/astra-anaconda.css$' \
        "$conf_dir/999-astra-retro-os-branding.conf"
    echo 'Astra Anaconda GTK logo, header and buttons configured'
    installed=$((installed+1))
fi

# WebUI: Fedora 45 Atomic can use the Cockpit/PatternFly installer.
# /usr/share/cockpit/branding/fedora/branding.css is selected with ID=fedora
# from os-release. Keep the original CSS and append scoped Anaconda rules.
# Handle Fedora variants, if installed, without altering the generic UI.
branding_root="$root/usr/share/cockpit/branding"
if [[ -d "$branding_root" ]]; then
    shopt -s nullglob
    for branddir in "$branding_root"/fedora "$branding_root"/fedora-*; do
        [[ -f "$branddir/branding.css" ]] || continue
        install -m 0644 "$source_logo" "$branddir/astra-anaconda-logo.png"
        # Idempotent in case the build re-runs the branding step.
        if ! grep -Fq 'ASTRA-ANACONDA-BRANDING-BEGIN' "$branddir/branding.css"; then
            printf '\n/* ASTRA-ANACONDA-BRANDING-BEGIN */\n' >> "$branddir/branding.css"
            cat "$script_dir/anaconda-webui.css" >> "$branddir/branding.css"
            printf '\n/* ASTRA-ANACONDA-BRANDING-END */\n' >> "$branddir/branding.css"
        fi
        grep -Fq 'ASTRA-ANACONDA-BRANDING-END' "$branddir/branding.css"
        echo "Astra Anaconda WebUI logo, header and buttons configured: ${branddir#"$root"}"
        installed=$((installed+1))
    done
fi

if (( installed == 0 )); then
    echo 'ERROR: Neither Anaconda GTK nor Fedora Cockpit branding assets were found.' >&2
    echo 'Check anaconda-live/anaconda-webui package installation order.' >&2
    exit 1
fi
