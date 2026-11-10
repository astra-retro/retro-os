#!/usr/bin/env bash
set -euo pipefail

src="${1:?Provide Live launcher directory}"

# Apply Anaconda-only branding after anaconda-live is installed.
# This leaves the GNOME launcher, wallpaper and installed OS untouched.
bash "$(dirname "${BASH_SOURCE[0]}")/anaconda/install.sh"

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
test -s /usr/share/icons/hicolor/512x512/apps/astra-retro-os.png || {
  echo "ERROR: Astra Retro OS launcher icon is missing" >&2
  exit 1
}
test -x /usr/bin/liveinst || {
  echo "ERROR: Anaconda Live launcher (/usr/bin/liveinst) is missing" >&2
  exit 1
}

install -d /usr/share/applications /etc/dconf/db/local.d /etc/dconf/profile

# Keep the Astra launcher ID which was already working as a GNOME dock
# favorite. Only brand the stock Anaconda entry (used for window matching).
install -m 0644 "$src/astra-retro-install.desktop" /usr/share/applications/astra-retro-install.desktop
install -m 0644 "$src/astra-retro-terminal.desktop" /usr/share/applications/astra-retro-terminal.desktop
rm -f /usr/share/applications/retro-os-install.desktop

if [[ -f /usr/share/applications/liveinst.desktop ]]; then
  sed -i -e '/^NoDisplay=/d' -e '/^Icon=/d' \
    /usr/share/applications/liveinst.desktop
  printf '\nIcon=/usr/share/icons/hicolor/512x512/apps/astra-retro-os.png\nNoDisplay=true\n' \
    >> /usr/share/applications/liveinst.desktop
fi

# Check the actual launcher pinned to the GNOME dock.
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate /usr/share/applications/astra-retro-install.desktop
fi
grep -qxF 'Icon=/usr/share/icons/hicolor/512x512/apps/astra-retro-os.png' /usr/share/applications/astra-retro-install.desktop

# Brand the GNOME Live welcome screen.
welcome="/usr/share/anaconda/gnome/fedora-welcome"
logo="/usr/share/icons/hicolor/scalable/apps/astra-retro-os.svg"

test -f "$welcome" || {
  echo "ERROR: Fedora Welcome not found" >&2
  exit 1
}

test -f "$logo" || {
  echo "ERROR: Astra logo not found" >&2
  exit 1
}

grep -q "iconName: 'fedora-logo-icon'" "$welcome" || {
  echo "ERROR: Unexpected Fedora Welcome format" >&2
  exit 1
}

sed -i \
  "s/iconName: 'fedora-logo-icon'/iconName: 'astra-retro-os'/" \
  "$welcome"

# Also brand the Welcome desktop entry.
desktop="/usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop"

if [[ -f "$desktop" ]]; then
  sed -i \
    -e 's/^Icon=.*/Icon=astra-retro-os/' \
    -e 's/^Name=.*/Name=Bienvenue dans Astra Retro OS/' \
    "$desktop"
fi

# Preserve an existing dconf profile; make sure it includes our local database.
if [[ ! -e /etc/dconf/profile/user ]]; then
  printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
elif ! grep -qxF 'system-db:local' /etc/dconf/profile/user; then
  printf '\nsystem-db:local\n' >> /etc/dconf/profile/user
fi

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
