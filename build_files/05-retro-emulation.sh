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
for tool in retro-emulation-setup retro-fetch-esde retro-launch-esde retro-install-emudeck; do
    test -s "/usr/libexec/retro-os/$tool"
    chmod 0755 "/usr/libexec/retro-os/$tool"
done

# For each graphical user login, try setup in the background. The service
# is idempotent; offline failures are retried at the next login.
mkdir -p /usr/lib/systemd/user/default.target.wants
ln -sfn ../retro-emulation-setup.service \
    /usr/lib/systemd/user/default.target.wants/retro-emulation-setup.service

# Fedora Atomic /etc is mutable; do not persist user config in the build image.
