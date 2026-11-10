#!/usr/bin/env bash
set -euo pipefail

# Run a real recursive bind mount in the same privileged Podman context as
# image-builder. If this fails, osbuild's container-deploy stage cannot work.
# The mount is isolated to this disposable container and is always unmounted.

echo "=== Host and Podman ==="
cat /etc/os-release | grep -E '^(NAME|VERSION_ID)=' || true
sudo podman version
sudo podman info --format '{{.Store.GraphRoot}}'

echo "=== Verify recursive bind mounts inside the builder container ==="
sudo podman run --rm --privileged \
  --userns=host \
  --security-opt apparmor=unconfined \
  --security-opt label=disable \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  --entrypoint /bin/sh \
  ghcr.io/osbuild/image-builder-cli:latest -ec '
    mkdir -p /run/osbuild/containers/storage
    mount --rbind /var/lib/containers/storage /run/osbuild/containers/storage
    mountpoint -q /run/osbuild/containers/storage
    umount -l /run/osbuild/containers/storage
    echo "OK: nested recursive bind mounts work"
  ' || {
  echo "ERROR: privileged container cannot perform recursive bind mounts." >&2
  echo "osbuild will fail at org.osbuild.container-deploy on this runner." >&2
  echo "Check the host AppArmor policy / privileged VM access." >&2
  exit 1
}
