#!/usr/bin/env bash
# Build only the Live environment; the RetroOS payload is left unchanged.
set -euo pipefail
: "${INSTALL_IMAGE_PAYLOAD:?Must supply an immutable RetroOS image ref}"

# This version deliberately uses a Fedora kernel for the Live environment.
# It does NOT remove OGC or any hardware support from the installed image.
dnf5 -y install \
    anaconda-live \
    libblockdev-btrfs libblockdev-lvm libblockdev-dm \
    dracut-live livesys-scripts \
    grub2-efi-x64-cdboot grub2-pc-modules \
    squashfs-tools xorriso jq podman

# Embed payload for offline Anaconda installation.
# IMPORTANT: package source is an OCI digest, not a moving :latest tag.
podman pull --authfile "${REGISTRY_AUTH_FILE}" "$INSTALL_IMAGE_PAYLOAD"
podman image exists "$INSTALL_IMAGE_PAYLOAD"

install -d /usr/share/anaconda /usr/share/applications /usr/lib/bootc-image-builder
printf '\nostreecontainer --url=%s --transport=containers-storage --no-signature-verification\n' \
  "$INSTALL_IMAGE_PAYLOAD" >> /usr/share/anaconda/interactive-defaults.ks

# Show a launcher on the GNOME live desktop; do not auto-run an installer.
cat > /usr/share/applications/retro-os-install.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install RetroOS
Comment=Install RetroOS on a disk
Exec=liveinst
Icon=system-software-install
Terminal=false
Categories=System;
DESKTOP

# Live session login, desktop, and initramfs.
if [[ -e /etc/sysconfig/livesys ]]; then
    sed -i 's/^livesys_session=.*/livesys_session=gnome/' /etc/sysconfig/livesys
fi
systemctl enable livesys.service livesys-late.service

# Larger /var/tmp for ostree installs in the live overlay (memory dependent).
install -d /etc/systemd/system /var/tmp
cat > /etc/systemd/system/var-tmp.mount <<'UNIT'
[Unit]
Description=RetroOS Live temporary workspace
[Mount]
What=tmpfs
Where=/var/tmp
Type=tmpfs
Options=size=50%,nr_inodes=1m
[Install]
WantedBy=local-fs.target
UNIT
systemctl enable var-tmp.mount

# Prevent modifications to the bundled Flatpak store in Live mode.
# Flatpaks are provisioned separately by RetroOS on first login.
install -d /boot/efi
cp -a /usr/lib/efi/*/*/EFI /boot/efi/

# Keep one and only one kernel for Titanoboa's ISO contract.
mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
if (( ${#kernels[@]} != 1 )); then
  printf 'Expected exactly one Fedora kernel, got %s\n' "${kernels[*]}" >&2
  exit 1
fi
kernel="${kernels[0]}"

# Generate the generic Fedora Live initramfs.
initramfs="/usr/lib/modules/${kernel}/initramfs.img"

DRACUT_NO_XATTR=1 dracut \
  --force \
  --verbose \
  --zstd \
  --reproducible \
  --no-hostonly \
  --add 'dmsquash-live dmsquash-live-autooverlay' \
  "$initramfs" "$kernel"

# Fail if the initramfs is missing or empty.
test -s "$initramfs" || {
  echo "ERROR: Live initramfs was not generated" >&2
  exit 1
}

# Verify that Dracut generated a readable archive.
lsinitrd "$initramfs" >/dev/null || {
  echo "ERROR: Cannot read generated initramfs" >&2
  exit 1
}

echo "Live initramfs successfully validated:"
ls -lh "$initramfs"

install -m 0644 \
  /usr/share/retro-os/iso.yaml \
  /usr/lib/bootc-image-builder/iso.yaml

dnf5 clean all
