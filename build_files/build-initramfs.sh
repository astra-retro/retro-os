#!/usr/bin/env bash
#
# Build an initramfs image for the installed kernel using dracut.
#
# Supports kernel flavors (e.g. "surface") and integrates with ostree/fido2.
#
set -xeuo pipefail

echo "::group::Build initramfs"
trap 'echo "::endgroup::"' EXIT

# Increase plymouth timeout
sed -i 's/^DeviceTimeout=.*/DeviceTimeout=15/' /usr/share/plymouth/plymouthd.defaults

# Set KERNEL_SUFFIX based on KERNEL_FLAVOR, defaulting to empty.
if [[ "${KERNEL_FLAVOR:-}" == "surface" ]]; then
    KERNEL_SUFFIX="surface"
else
    KERNEL_SUFFIX=""
fi

# Retrieve the installed kernel version with architecture using dnf5.
QUALIFIED_KERNEL="$(
    dnf5 repoquery \
        --installed \
        --queryformat='%{evr}.%{arch}' \
        "kernel${KERNEL_SUFFIX:+-${KERNEL_SUFFIX}}"
)"
INITRAMFS="/usr/lib/modules/${QUALIFIED_KERNEL}/initramfs.img"

# Exclude build-specific metadata from the initramfs.
OS_RELEASE="/usr/lib/os-release"
TMP_OS_RELEASE=$(mktemp --tmpdir 'os-release-XXXXXXXXXX')
cp "${OS_RELEASE}" "${TMP_OS_RELEASE}"
sed -Ei -e '/^((OSTREE_)?(IMAGE_)?VERSION|PRETTY_NAME|BUILD_ID|BOOTLOADER_NAME|IMAGE_ID)=/d' "${OS_RELEASE}"

# Generate a reproducible initramfs with ostree and fido2 support.
DRACUT_NO_XATTR=1 /usr/bin/dracut \
    --no-hostonly \
    --kver "${QUALIFIED_KERNEL}" \
    --reproducible \
    --zstd \
    -v \
    --add ostree \
    --add fido2 \
    --add plymouth \
    --add astra-plymouth \
    -f "${INITRAMFS}"

# Copy back to preserve the original os-release permissions.
cp "${TMP_OS_RELEASE}" "${OS_RELEASE}"
rm "${TMP_OS_RELEASE}"

# Detect silent regression in generic initramfs builds: the stock Dracut
# Plymouth module can select text/details instead of the custom Astra theme.
# Failing the OCI build is safer than shipping another broken boot splash.
test -s "${INITRAMFS}"
if [[ "$(plymouth-set-default-theme)" != "astra-retro-os" ]]; then
    echo 'ERROR: Astra Plymouth is not the selected default theme' >&2
    exit 1
fi
initramfs_manifest="$(mktemp --tmpdir 'astra-initramfs-XXXXXXXXXX')"
trap 'rm -f "$initramfs_manifest"; echo "::endgroup::"' EXIT
lsinitrd "${INITRAMFS}" > "$initramfs_manifest"
for required in \
    'usr/share/plymouth/themes/astra-retro-os/astra-retro-os.plymouth' \
    'usr/share/plymouth/themes/astra-retro-os/astra-retro-os.script' \
    'usr/share/plymouth/themes/astra-retro-os/plymouth-splash.png' \
    'usr/share/plymouth/themes/astra-retro-os/astra-title.png' \
    'usr/share/plymouth/themes/astra-retro-os/spinner.png' \
    'usr/share/plymouth/themes/default.plymouth'; do
    if ! grep -Fq "$required" "$initramfs_manifest"; then
        echo "ERROR: Missing Plymouth asset in installed initramfs: $required" >&2
        exit 1
    fi
done
if ! grep -Eq '(usr/)?lib(64)?/plymouth/script[.]so' "$initramfs_manifest"; then
    echo 'ERROR: Missing Plymouth script plugin in installed initramfs' >&2
    exit 1
fi
echo 'Astra Plymouth script theme and plugin verified in installed initramfs'
rm -f "$initramfs_manifest"

# Restrict read/write access to root only.
chmod 0600 "${INITRAMFS}"
