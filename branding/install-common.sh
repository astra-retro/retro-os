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
install -m 0644 "$script_dir/plymouth/astra-title.png" /usr/share/plymouth/themes/astra-retro-os/astra-title.png

cat > /etc/dconf/db/local.d/20-astra-retro-os <<'DCONF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/astra-retro-os/wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/astra-retro-os/wallpaper.png'
picture-options='zoom'

# Fedora's GNOME Background Logo extension overlays the logo in the corner.
# Replace its Fedora defaults with the shared Astra logo in both themes.
[org/fedorahosted/background-logo-extension]
logo-file='/usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg'
logo-file-dark='/usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg'
logo-position='bottom-right'
logo-always-visible=true
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

# The Background Logo extension changed its GSettings schema in Fedora 45.
# Detect the installed version; do not write only to the obsolete fedorahosted path.
# Install both dconf defaults and a GLib schema override, because Live sessions
# can use a different dconf profile and would otherwise keep Fedora's defaults.
if command -v gsettings >/dev/null && command -v glib-compile-schemas >/dev/null; then
  available_schemas="$(gsettings list-schemas)"
  background_logo_schema=''
  for candidate in \
    org.gnome.shell.extensions.background-logo \
    org.fedorahosted.background-logo-extension; do
    if grep -Fxq "$candidate" <<< "$available_schemas"; then
      background_logo_schema="$candidate"
      break
    fi
  done

  if [[ -n "$background_logo_schema" ]]; then
    logo_keys="$(gsettings list-keys "$background_logo_schema")"
    if ! grep -Fxq 'logo-file' <<< "$logo_keys"; then
      echo "ERROR: Unexpected Background Logo schema keys ($background_logo_schema):" >&2
      printf '%s\n' "$logo_keys" >&2
      exit 1
    fi

    logo_file='/usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg'
    schema_path="${background_logo_schema//./\/}"
    override='/usr/share/glib-2.0/schemas/95-astra-background-logo.gschema.override'
    dconf_file='/etc/dconf/db/local.d/25-astra-background-logo'
    install -d "$(dirname "$override")" "$(dirname "$dconf_file")"
    printf '[%s]\nlogo-file=\x27%s\x27\n' "$background_logo_schema" "$logo_file" > "$override"
    printf '[%s]\nlogo-file=\x27%s\x27\n' "$schema_path" "$logo_file" > "$dconf_file"

    if grep -Fxq 'logo-file-dark' <<< "$logo_keys"; then
      printf 'logo-file-dark=\x27%s\x27\n' "$logo_file" >> "$override"
      printf 'logo-file-dark=\x27%s\x27\n' "$logo_file" >> "$dconf_file"
    fi
    if grep -Fxq 'logo-always-visible' <<< "$logo_keys"; then
      printf 'logo-always-visible=true\n' >> "$override"
      printf 'logo-always-visible=true\n' >> "$dconf_file"
    fi

    glib-compile-schemas --strict /usr/share/glib-2.0/schemas
    dconf update
    echo "Configured Astra desktop overlay for $background_logo_schema"
  else
    echo 'Note: GNOME Background Logo extension not installed; no overlay branding needed.'
  fi
else
  echo 'Note: GSettings tools unavailable; skipping background-logo schema defaults.'
fi

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

# Fedora's GNOME Settings About page may use a distributor logo compiled
# into gnome-control-center, instead of resolving LOGO= from os-release.
# Fedora's light and dark assets are provided by the fedora-logos package.
# Install our common Astra logo at those expected paths in both OCI images.
# Run this after package installation so the Fedora RPM does not restore them.
# GNOME Settings renders these distributor pixmaps at a large size. Use a
# dedicated 256x256 image with a centered 128px logo; keep the full-size
# Astra icon for GNOME Shell, Plymouth and other applications.
about_logo="$assets/gnome-about-logo.png"
test -s "$about_logo" || { echo "Missing About logo: $about_logo" >&2; exit 1; }
install -d /usr/share/pixmaps
for settings_logo in fedora_logo_med.png fedora_whitelogo_med.png; do
  install -m 0644 "$about_logo" "/usr/share/pixmaps/$settings_logo"
done

command -v plymouth-set-default-theme >/dev/null || { echo 'plymouth required' >&2; exit 1; }
plymouth-set-default-theme astra-retro-os
if [[ "$mode" == installed ]]; then
  # The image is installed through Anaconda/bootc; persistent /boot cannot be
  # modified while constructing the OCI container. Ship a first-boot sync.
  install -D -m 0755 "$script_dir/sync-installed-boot.sh" /usr/libexec/astra-retro-os/sync-installed-boot
  install -D -m 0644 "$script_dir/systemd/astra-installed-boot.service" /usr/lib/systemd/system/astra-installed-boot.service
  install -D -m 0644 "$script_dir/systemd/astra-installed-boot.path" /usr/lib/systemd/system/astra-installed-boot.path
  systemctl enable astra-installed-boot.service astra-installed-boot.path

  # Anaconda/bootc imports these normal-boot kernel arguments when installing
  # and keeps them updated with subsequent deployments; leave debug BLS verbose.
  install -D -m 0644 "$script_dir/kargs/10-astra-graphical-boot.toml" \
    /usr/lib/bootc/kargs.d/10-astra-graphical-boot.toml

  # The installed initramfs is generic (--no-hostonly): some Dracut releases
  # otherwise select only the fallback text theme, so bundle our script theme.
  install -D -m 0644 "$script_dir/dracut/51astra-plymouth/module-setup.sh" \
    /usr/lib/dracut/modules.d/51astra-plymouth/module-setup.sh
fi
printf 'Astra branding installed (%s)\n' "$mode"
