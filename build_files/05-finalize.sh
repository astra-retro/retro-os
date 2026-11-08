#!/usr/bin/env bash
#
# Final cleanup, service configuration, and image finalization for Bazzite.
#
set -xeuo pipefail

echo "::group::Finalize bazzite image"
trap 'echo "::endgroup::"' EXIT

# -- Basic cleanup and setup --
echo "==> Performing basic cleanup..."
mkdir -p /var/tmp
chmod 1777 /var/tmp

# -- Hide unnecessary desktop entries --
echo "==> Hiding unnecessary desktop entries..."
desktop-file-edit --set-key=Hidden --set-value=true \
    /usr/share/applications/nvtop.desktop
desktop-file-edit --set-key=Hidden --set-value=true \
    /usr/share/applications/btop.desktop
desktop-file-edit --set-key=Hidden --set-value=true \
    /usr/share/applications/yad-icon-browser.desktop
rm -f /usr/share/applications/com.microsoft.edit.desktop

# -- Configure Bluetooth input --
echo "==> Configuring Bluetooth input..."
sed -i \
    's/#UserspaceHID.*/UserspaceHID=true/' \
    /etc/bluetooth/input.conf

# -- Configure Flatpak --
echo "==> Configuring Flatpak..."
mkdir -p /etc/flatpak/remotes.d
curl --fail --retry 3 --retry-all-errors -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# -- Configure systemd services --
echo "==> Configuring systemd services..."
systemctl disable fw-fanctrl.service
systemctl enable input-remapper.service
systemctl enable greenboot-healthcheck.service
systemctl enable greenboot-set-rollback-trigger.service
systemctl enable bluetooth.service
