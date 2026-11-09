#!/usr/bin/env bash
# Install common Astra Retro OS branding into either bootc OCI image.
# Usage: install-common.sh ASSET_DIR [installed|live]
set -euo pipefail
assets="${1:?Provide asset directory}"
mode="${2:-installed}"
case "$mode" in installed|live) ;; *) echo "Unknown mode: $mode" >&2; exit 2;; esac
for f in wallpaper.png boot-background.png grub-background.png plymouth-splash.png astra-retro-os-logo.svg astra-retro-os-logo.png; do
  test -s "$assets/$f" || { echo "Missing branding asset: $assets/$f" >&2; exit 1; }
done

install -d /usr/share/backgrounds/astra-retro-os \
  /usr/share/plymouth/themes/astra-retro-os \
  /usr/share/icons/hicolor/scalable/apps \
  /usr/share/icons/hicolor/512x512/apps \
  /usr/share/astra-retro-os \
  /etc/dconf/db/local.d
install -m 0644 "$assets/wallpaper.png" /usr/share/backgrounds/astra-retro-os/wallpaper.png
install -m 0644 "$assets/boot-background.png" /usr/share/astra-retro-os/boot-background.png
install -m 0644 "$assets/grub-background.png" /usr/share/astra-retro-os/grub-background.png
install -m 0644 "$assets/astra-retro-os-logo.svg" /usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg
install -m 0644 "$assets/astra-retro-os-logo.png" /usr/share/icons/hicolor/512x512/apps/astra-retro-os.png
install -m 0644 "$assets/plymouth-splash.png" /usr/share/plymouth/themes/astra-retro-os/plymouth-splash.png
# The scripts are in the same stage/mount as the assets.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -m 0644 "$script_dir/plymouth/astra-retro-os.plymouth" /usr/share/plymouth/themes/astra-retro-os/astra-retro-os.plymouth
install -m 0644 "$script_dir/plymouth/astra-retro-os.script" /usr/share/plymouth/themes/astra-retro-os/astra-retro-os.script
install -m 0644 "$script_dir/plymouth/spinner.png" /usr/share/plymouth/themes/astra-retro-os/spinner.png

cat > /etc/dconf/db/local.d/20-astra-retro-os <<'DCONF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/astra-retro-os/wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/astra-retro-os/wallpaper.png'
picture-options='zoom'
DCONF
# Do not replace an existing user dconf profile; ensure its local database is reachable.
install -d /etc/dconf/profile
if [[ ! -e /etc/dconf/profile/user ]]; then
  printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
elif ! grep -qxF 'system-db:local' /etc/dconf/profile/user; then
  printf '\nsystem-db:local\n' >> /etc/dconf/profile/user
fi
command -v dconf >/dev/null || { echo 'dconf required' >&2; exit 1; }
dconf update

# Preserve ID=fedora, ID_LIKE, VERSION_ID and OSTREE metadata for compatibility.
release=/usr/lib/os-release
if [[ -f "$release" ]]; then
  sed -i -E '/^(NAME|PRETTY_NAME|LOGO)=/d' "$release"
  if [[ "$mode" == live ]]; then
    printf 'NAME="Astra Retro OS"\nPRETTY_NAME="Astra Retro OS Live"\nLOGO=astra-retro-os\n' >> "$release"
  else
    printf 'NAME="Astra Retro OS"\nPRETTY_NAME="Astra Retro OS"\nLOGO=astra-retro-os\n' >> "$release"
  fi
fi

command -v plymouth-set-default-theme >/dev/null || { echo 'plymouth required' >&2; exit 1; }
plymouth-set-default-theme astra-retro-os
printf 'Astra branding installed (%s)\n' "$mode"
