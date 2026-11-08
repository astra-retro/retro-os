#!/usr/bin/env bash
#
# Initialize
#
# Setup Copr repositories
#
set -xeuo pipefail

echo "::group::Initialize"
trap 'echo "::endgroup::"' EXIT

# -- Cache configuration --
# Ensure cache directory exists and enable package caching in DNF.
echo "==> Configuring DNF cache..."
mkdir -p /var/roothome
dnf5 config-manager setopt keepcache=1

# -- Enable Copr repositories --
# Enable each Copr repo and set its priority to 98.
echo "==> Enabling Copr repositories..."

for copr in \
    ublue-os/staging \
    ublue-os/packages \
    che/nerd-fonts; \
do
    echo "    Enabling copr: ${copr}..."
    dnf5 -y copr enable "${copr}"
    dnf5 -y config-manager \
        setopt "copr:copr.fedorainfracloud.org:${copr////:}.priority=98"
done

# Disable third party copr repos
dnf5 -y copr disable "che/nerd-fonts"