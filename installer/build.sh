#!/usr/bin/env bash
# Build only the Live environment; the RetroOS payload is left unchanged.
set -euo pipefail
: "${INSTALL_IMAGE_PAYLOAD:?Must supply an immutable RetroOS image ref}"
: "${INSTALL_IMAGE_TRACKING_REF:?Must supply the remote OCI update tag}"
[[ "$INSTALL_IMAGE_PAYLOAD" =~ ^ghcr\.io/[a-z0-9_.-]+/[a-z0-9_.-]+@sha256:[a-f0-9]{64}$ ]] || {
  echo "ERROR: Offline source must be a GHCR OCI digest" >&2; exit 1;
}
[[ "$INSTALL_IMAGE_TRACKING_REF" =~ ^ghcr\.io/[a-z0-9_.-]+/[a-z0-9_.-]+:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$ ]] || {
  echo "ERROR: Update source must be a GHCR tag" >&2; exit 1;
}

# This version deliberately uses a Fedora kernel for the Live environment.
# It does NOT remove OGC or any hardware support from the installed image.
dnf5 -y install \
    anaconda-live \
    libblockdev-btrfs libblockdev-lvm libblockdev-dm \
    dracut-live livesys-scripts \
    grub2-efi-x64-cdboot grub2-pc-modules \
    squashfs-tools xorriso jq podman pykickstart \
    gnome-shell-extension-dash-to-dock

dnf5 -y install plymouth-plugin-script dconf ptyxis
# French translations and locale data are needed in the Live environment.
dnf5 -y install glibc-langpack-fr langpacks-fr
bash /usr/share/retro-os/branding/install-common.sh /usr/share/retro-os/branding/assets live
bash /usr/share/retro-os/branding/install-live.sh /usr/share/retro-os/branding/live

# Fedora Atomic live images expose /mnt as a symlink to /var/mnt. Anaconda
# passes --root=/mnt/sysroot to systemd-tmpfiles, while systemd canonicalizes
# its SELinux root to /var/mnt/sysroot. Relabelling then fails with code 73:
# "Path ... is not under root ..., refusing SELinux label fix."
# Canonicalize only the root argument in the Live Anaconda implementation.
# Keep SELinux enabled and leave the installed OSTree payload untouched.
python3 - <<'PY'
from pathlib import Path

paths = sorted(Path("/usr").glob(
    "lib*/python*/site-packages/pyanaconda/modules/payloads/"
    "payload/rpm_ostree/installation.py"
))
if len(paths) != 1:
    raise SystemExit(
        f"Expected exactly one Anaconda RPM-OSTree source file, found: {paths}"
    )

source_path = paths[0]
source = source_path.read_text(encoding="utf-8")
old = '"--root=" + self._sysroot,'
new = '"--root=" + os.path.realpath(self._sysroot),'
if source.count(old) != 1 or "\nimport os\n" not in source:
    raise SystemExit("Anaconda source changed; refusing to apply an unsafe patch")

patched = source.replace(old, new, 1)
compile(patched, str(source_path), "exec")
source_path.write_text(patched, encoding="utf-8")
print(f"Applied Astra SELinux tmpfiles root-path fix: {source_path}")
PY

# Brand the Fedora Live welcome screen.
welcome=/usr/share/anaconda/gnome/fedora-welcome

if [[ -f "$welcome" ]]; then
    sed -i \
        "s/iconName: 'fedora-logo-icon'/iconName: 'astra-retro-os'/" \
        "$welcome"
    sed -i \
        -e 's/Welcome to Fedora!/Bienvenue dans Astra Retro OS !/g' \
        -e 's/Install Fedora…/Installer Astra Retro OS…/g' \
        "$welcome"
fi

# French defaults for the Live ISO only. The installed bootc OCI payload is untouched.
# Write files directly: systemd-localed is not running during the container build.
install -d /etc/X11/xorg.conf.d /etc/dconf/db/local.d
printf 'LANG=fr_FR.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=fr\n' > /etc/vconsole.conf
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'XKB'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
EndSection
XKB
cat > /etc/dconf/db/local.d/30-astra-live-keyboard <<'DCONF'
[org/gnome/desktop/input-sources]
sources=[('xkb', 'fr')]
xkb-options=@as []
DCONF
dconf update

# Refuse to publish a Live image with an unavailable locale.
locale -a | grep -Ei '^fr_FR\.utf-?8$' >/dev/null || {
  echo 'ERROR: French locale unavailable in the Live image' >&2
  exit 1
}
# Embed payload for offline Anaconda installation.
# IMPORTANT: package source is an OCI digest, not a moving :latest tag.
podman pull --authfile "${REGISTRY_AUTH_FILE}" "$INSTALL_IMAGE_PAYLOAD"
podman image exists "$INSTALL_IMAGE_PAYLOAD"

install -d /usr/share/anaconda /usr/share/applications /usr/lib/bootc-image-builder
# Fedora 45 bootc Kickstart keeps a local offline digest source distinct
# from the remote tag recorded for future updates.
printf '\nbootc --source-imgref containers-storage:%s --target-imgref %s\n' \
  "$INSTALL_IMAGE_PAYLOAD" "$INSTALL_IMAGE_TRACKING_REF" \
  >> /usr/share/anaconda/interactive-defaults.ks
# The pykickstart RPM (not python3-kickstart) provides /usr/bin/ksvalidator.
# Validate the generated Kickstart in the same Fedora 45 image as Anaconda.
command -v ksvalidator >/dev/null || {
  echo 'ERROR: ksvalidator not found; pykickstart must be installed' >&2; exit 1;
}
ksvalidator -v F45 /usr/share/anaconda/interactive-defaults.ks

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
