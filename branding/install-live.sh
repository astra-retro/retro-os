#!/usr/bin/env bash
set -euo pipefail
src="${1:?Provide Live launcher directory}"
install -d /usr/share/applications /etc/dconf/db/local.d
for f in astra-retro-install.desktop astra-retro-terminal.desktop; do
  install -m 0644 "$src/$f" "/usr/share/applications/$f"
done
cat > /etc/dconf/db/local.d/30-astra-live <<'DCONF'
[org/gnome/shell]
favorite-apps=['astra-retro-install.desktop', 'astra-retro-terminal.desktop', 'org.gnome.Nautilus.desktop']
DCONF
dconf update
