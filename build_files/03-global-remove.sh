#!/usr/bin/env bash
#
# Remove pre installed packages.
#
# This script removes packages that are replaced by flatpaks or
# alternative tools.
#
set -xeuo pipefail

echo "::group::Globally remove packages"
trap 'echo "::endgroup::"' EXIT

# -- Define packages to remove --
# Packages to remove.
# Not quoted in the array so brace expansion and multiple words expand
# correctly into individual dnf arguments.
declare -a REMOVE_GLOBAL=(
    firefox{,-langpacks}      # we use the flatpak
    htop                      # btop is better
    toolbox                   # distrobox is better
)

# -- Remove the packages --
echo "==> Removing packages with dnf5..."
dnf5 -y remove "${REMOVE_GLOBAL[@]}"
