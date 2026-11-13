#!/usr/bin/env bash
set -euo pipefail

# Package the RetroOS helper scripts, units and launchers BEFORE the
# emulation setup checks their presence. "overrides" is a separate tree.
if [[ ! -d /tmp/system_files/retro-emulation/usr ]]; then
    echo 'ERROR: system_files/retro-emulation/usr staging tree missing' >&2
    exit 1
fi
cp --archive --verbose --force /tmp/system_files/retro-emulation/usr/. /usr/

# Package all bootstrap tools in immutable /usr. Do not install Flatpaks
# or EmuDeck in the build container: their state belongs in /var/home.
for tool in retro-emulation-setup retro-fetch-esde retro-launch-esde retro-install-emudeck retro-configure-esde; do
    test -s "/usr/libexec/retro-os/$tool"
    chmod 0755 "/usr/libexec/retro-os/$tool"
done

# The splash must exist inside the OCI image; no runtime network fetch.
test -s /usr/share/retro-os/esde/splash.svg || {
    echo 'ERROR: Astra ES-DE splash.svg is missing from the OCI image' >&2
    exit 1
}
grep -q '<svg ' /usr/share/retro-os/esde/splash.svg

# For each graphical user login, try setup in the background. The service
# is idempotent; offline failures are retried at the next login.
mkdir -p /usr/lib/systemd/user/default.target.wants
ln -sfn ../retro-emulation-setup.service \
    /usr/lib/systemd/user/default.target.wants/retro-emulation-setup.service

# Additional portable utilities, pinned to upstream releases and verified
# against their published SHA-256 checksums before being staged in /usr.
# Build-time installation only: no network fetch on the installed system.
bash /ctx/tools/install-retro-utilities.sh

# Fedora Atomic /etc is mutable; do not persist user config in the build image.
