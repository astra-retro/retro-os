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

# -- Install Terra-release packages --
# Add the Terra repository and install its release packages.
echo "==> Installing Terra release packages..."
# DNF expands releasever, not the build shell.
# shellcheck disable=SC2016
dnf5 -y install \
    --nogpgcheck \
    --setopt=terra.skip_if_unavailable=False \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release{,-extras,-mesa}

dnf5 config-manager setopt '*terra*.skip_if_unavailable=False'

# -- Enable negativo17 multimedia repository --
echo "==> Enabling negativo17 multimedia repository..."
dnf5 config-manager enable 'fedora-multimedia*'

# -- Configure repository priorities and exclusions --
# Set priority and exclusion rules for each repository.
echo "==> Configuring repository priorities and exclusions..."

dnf5 -y config-manager \
    setopt "*terra*".priority=1 \
           "*terra*.exclude=nerd-fonts"
