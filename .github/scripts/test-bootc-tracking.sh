#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n installer/build.sh
python3 - <<'PY'
from pathlib import Path
files = {name: Path(name).read_text() for name in [
    ".github/workflows/build-pr.yml",
    ".github/workflows/build-live-iso.yml",
    ".github/workflows/build-disk.yml",
    ".github/workflows/build.yml",
    "installer/Containerfile",
    "installer/build.sh",
]}
pr = files[".github/workflows/build-pr.yml"]
assert "pr-${PR_NUMBER}" in pr
assert "pr-${PR_NUMBER}-" not in pr or "pr-${PR_NUMBER}" in pr
assert "tracking_ref=$tracking_ref" in pr
assert "gh api" in pr and "current" in pr
assert pr.count("tracking_ref: ${{ needs.publish-oci.outputs.tracking_ref }}") == 2
assert "target=\"ghcr.io/${GITHUB_REPOSITORY,,}:${IMAGE_TAG}\"" in pr

iso = files[".github/workflows/build-live-iso.yml"]
assert 'INSTALL_IMAGE_TRACKING_REF=$RETRO_TRACKING_REF' in iso
assert 'printf \'payload=%s\\ntracking=%s\\n\'' in iso
assert 'sudo podman pull "$payload"' in iso
disk = files[".github/workflows/build-disk.yml"]
assert 'sudo podman tag "$digest" "$TRACKING_REF"' in disk
assert 'BOOTC_REF: ${{ steps.image.outputs.tracking_ref }}' in disk
assert 'sudo podman pull "$digest"' in disk

ks = files["installer/build.sh"]
assert 'bootc --source-imgref containers-storage:%s --target-imgref %s' in ks
assert 'ksvalidator -v F45' in ks
assert 'squashfs-tools xorriso jq podman pykickstart' in ks, (
    'The Fedora pykickstart RPM supplies the ksvalidator binary'
)
assert "ostreecontainer --url=" not in ks
assert 'INSTALL_IMAGE_TRACKING_REF' in files["installer/Containerfile"]

release = files[".github/workflows/build.yml"]
assert "tags:\n      - 'v*'" in release
assert 'git merge-base --is-ancestor HEAD origin/main' in release
assert 'alias_tags+=" stable"' in release
assert 'git fetch --no-tags origin main' in release
PY
echo "Bootc channel workflow checks passed"
