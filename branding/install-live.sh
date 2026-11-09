#!/usr/bin/env bash
set -euo pipefail

src="${1:?Provide Live launcher directory}"

# Dash to Dock is a Fedora RPM, installed in installer/build.sh.
# Fail during the image build rather than shipping an invisible dock.
test -d /usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com || {
  echo "ERROR: Dash to Dock is not installed" >&2
  exit 1
}

# Shared branding must be installed before the Live-specific branding.
test -s /usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg || {
  echo "ERROR: Astra Retro OS logo is missing" >&2
  exit 1
}

install -d /usr/share/applications /etc/dconf/db/local.d /etc/dconf/profile
for f in astra-retro-install.desktop astra-retro-terminal.desktop; do
  install -m 0644 "$src/$f" "/usr/share/applications/$f"
done

# Preserve an existing dconf profile; make sure it includes our local database.
if [[ ! -e /etc/dconf/profile/user ]]; then
  printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
elif ! grep -qxF 'system-db:local' /etc/dconf/profile/user; then
  printf '\nsystem-db:local\n' >> /etc/dconf/profile/user
fi

# Hide the generic Anaconda entry from the applications grid; the custom
# Astra launcher remains available and runs the exact same liveinst command.
# Retain the original desktop file for application identity/window matching.
if [[ -f /usr/share/applications/liveinst.desktop ]]; then
  sed -i -e '/^NoDisplay=/d' -e '/^Icon=/d' \
    /usr/share/applications/liveinst.desktop
  printf '\nIcon=astra-retro-os\nNoDisplay=true\n' \
    >> /usr/share/applications/liveinst.desktop
fi
rm -f /usr/share/applications/retro-os-install.desktop

cat > /etc/dconf/db/local.d/30-astra-live <<'DCONF'
[org/gnome/shell]
# Enable the fixed dock; keep Fedora's existing background-logo extension.
enabled-extensions=['dash-to-dock@micxgx.gmail.com', 'background-logo@fedorahosted.org']
favorite-apps=['astra-retro-install.desktop', 'astra-retro-terminal.desktop', 'org.gnome.Nautilus.desktop']

[org/gnome/shell/extensions/dash-to-dock]
dock-position='BOTTOM'
dock-fixed=true
autohide=false
intellihide=false
extend-height=false
dash-max-icon-size=48
show-show-apps-button=true
DCONF

dconf update
