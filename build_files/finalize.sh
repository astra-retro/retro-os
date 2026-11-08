#!/usr/bin/env bash
#
# Finalize the system image: clean caches, relocate accounts, and remove
# stale lock files to produce a minimal, portable root filesystem.
#
set -xeuo pipefail

echo "::group::Finalize image"
trap 'echo "::endgroup::"' EXIT

# Tell DNF5 not to keep downloaded package cache after installation.
dnf5 config-manager setopt keepcache=0

# -- Restore DNF fallback after all package transactions --
echo "==> Restoring DNF fallback..."
dnf5 config-manager unsetopt '*terra*.skip_if_unavailable'
dnf5 config-manager setopt skip_if_unavailable=1

# -- Disable rpm-ostree stage --
echo "==> Disabling rpm-ostree stage..."
sed -i \
    's/stage/none/g' \
    /etc/rpm-ostreed.conf

# -- Disable Copr repositories --
echo "==> Disabling Copr repositories..."
for copr in \
    ublue-os/staging \
    ublue-os/packages \
    che/nerd-fonts; do
    dnf5 -y copr disable "${copr}"
done

# Move user/group entries from /etc to /usr/lib so they persist across
# chroots and container mounts.
relocate_accounts() {
    local etc="$1" lib="$2" shadow="$3" keep="$4" reset="$5"
    local out line name

    [ -f "$etc" ] || return 0
    out=$(grep -vE -- "${keep}" "${etc}") || true
    [ -n "$out" ] || return 0

    echo
    echo "Moving the following entries from ${etc} to ${lib}"
    echo "${out}"

    { cat "${lib}" 2>/dev/null || true; echo "${out}"; } > "${lib}.new"
    mv -f "${lib}.new" "${lib}"

    # Fail the build rather than ship an image where these went missing.
    while IFS= read -r line; do
        if ! grep -qxF -- "${line}" "${lib}"; then
            echo "ERROR: '${line}' did not persist in ${lib}" >&2
            return 1
        fi
    done <<< "${out}"

    printf '%s\n' "${reset}" > "${etc}"

    if [ -f "${shadow}" ]; then
        while IFS= read -r line; do
            name="${line%%:*}"
            sed -i "/^${name}:/d" "${shadow}"
        done <<< "${out}"
    fi
}

relocate_accounts /etc/passwd /usr/lib/passwd /etc/shadow \
    'root' 'root:x:0:0:root:/root:/bin/bash'
relocate_accounts /etc/group /usr/lib/group /etc/gshadow \
    'root|wheel' 'root:x:0:
wheel:x:10:'

# Delete any remaining unnecessary files.
rm -rf \
    /etc/.pwd.lock \
    /etc/passwd- \
    /etc/group- \
    /etc/shadow- \
    /etc/gshadow- \
    /etc/subuid- \
    /etc/subgid-

# Chunkah
# See: https://github.com/coreos/chunkah#customizing-the-layers
assign_chunk() {
    local component="$1" interval="$2" path
    shift 2
    for path in "$@"; do
        if [[ -e "${path}" && ! -L "${path}" ]]; then
            setfattr -n user.component -v "${component}" "${path}"
            setfattr -n user.update-interval -v "${interval}" "${path}"
        fi
    done
}
export -f assign_chunk

assign_chunk rpm-ostree-tmpfiles.d quarterly /usr/lib/rpm-ostree/tmpfiles.d

assign_chunk ublue-os quarterly \
    /usr/share/ublue-os

assign_chunk ublue-os-config yearly \
    /etc/flatpak/remotes.d/flathub.flatpakrepo \
    /usr/lib/dracut/dracut.conf.d/10-compression.conf \
    /usr/lib/systemd/system/bootc-update-ca-trust.service \
    /usr/lib/systemd/system/bootc-update-crypto-policies.service \
    /usr/lib/systemd/system/flatpak-add-fedora-repos.service \
    /usr/lib/systemd/system-generators/coreos-sulogin-force-generator \
    /usr/lib/tmpfiles.d/coredump.conf \
    /usr/share/dnf/plugins/copr.vendor.conf


for GNOME_EXTENSION in /usr/share/gnome-shell/extensions/*; do
    if [[ -d "${GNOME_EXTENSION}" ]]; then
        assign_chunk "gnome-extension-${GNOME_EXTENSION##*/}" weekly "${GNOME_EXTENSION}"
    fi
done

assign_chunk fontconfig-cache daily /usr/lib/fontconfig/cache
assign_chunk jupiter-dock-updater quarterly /usr/libexec/jupiter-dock-updater
assign_chunk ublue-docs quarterly /usr/share/ublue-os/docs

# Catch files changed since the last stage's reset (initramfs, image-info, overrides).
/ctx/reset-mtimes.sh
