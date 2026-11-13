#!/usr/bin/env bash
# Install the upstream Linux builds of the additional retro utilities.
# All URLs are fixed release assets and are checked against the SHA-256
# published by each project's GitHub release. Never fetch "latest" at build.
set -euo pipefail

arch="$(uname -m)"
case "$arch" in
  x86_64)
    ps3dec_target='x86_64-unknown-linux-gnu'
    ps3dec_sha='60cb11d4b42e633b270dd3fc1e3a1ff1de478222702d8a35688794ba4b64972b'
    rusty_arch='x86_64'
    rusty_cli_sha='e3f347414c25ad17c96775fb9dc5d427d885a07b64488c6ff071ca9a4118e3ec'
    rusty_gui_sha='9c506fc27c6693af23b30edbc02447f8cfb76021a1edfcd1a937328d25af920e'
    skyscraper_arch='x86_64'
    skyscraper_sha='a97f0c70e14ee07a28c3b5ca5055f3e679c433c44812780380bed4966853072f'
    ;;
  aarch64)
    ps3dec_target='aarch64-unknown-linux-gnu'
    ps3dec_sha='e351a3e5c719a6a46e955ab6f85a25c1e1ff54ac27e3964d842784f29b023b83'
    rusty_arch='arm64'
    rusty_cli_sha='c11a1d631373ba0da9f9f1c07ca0d03ec0689530104b389df051e78937fd0a43'
    rusty_gui_sha='39734dc7a67be3d4e0894e2b9df79b2594f6ec39526a8bf4ea74c2f16270e2c0'
    skyscraper_arch='aarch64'
    skyscraper_sha='6da4c16d94334b2275bf3629222f936d7786469f4cd863b83ab1934368715ac1'
    ;;
  *)
    echo "ERROR: unsupported architecture for retro tools: $arch" >&2
    exit 1
    ;;
esac

for cmd in curl sha256sum tar unzip find install; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing build tool $cmd" >&2; exit 1; }
done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

download_checked() {
  local url="$1" checksum="$2" dst="$3"
  curl --fail --location --retry 4 --retry-all-errors --silent --show-error \
    --output "$dst" "$url"
  printf '%s  %s\n' "$checksum" "$dst" | sha256sum -c -
}

# 1. Redrrx/ps3dec, CLI (MIT), for decrypting legally owned PS3 ISOs
# using a key supplied by the user; no decryption keys are bundled.
ps3dec_version='v3.0.0'
ps3dec_asset="ps3dec-${ps3dec_target}.tar.gz"
download_checked \
  "https://github.com/Redrrx/ps3dec/releases/download/${ps3dec_version}/${ps3dec_asset}" \
  "$ps3dec_sha" "$tmp/ps3dec.tar.gz"
mkdir -p "$tmp/ps3dec"
tar -xzf "$tmp/ps3dec.tar.gz" -C "$tmp/ps3dec"
mapfile -d '' -t ps3dec_binaries < <(find "$tmp/ps3dec" -type f -name ps3dec -print0)
if (( ${#ps3dec_binaries[@]} != 1 )); then
  echo "ERROR: expected exactly one ps3dec binary in $ps3dec_asset" >&2
  exit 1
fi
install -D -m 0755 "${ps3dec_binaries[0]}" /usr/bin/ps3dec

# 2. RainbowCookie32/rusty-psn, separate egui and CLI builds (MIT).
# Install the egui binary as rusty-psn and the CLI as rusty-psn-cli.
rusty_version='v0.7.1'
install_rusty() {
  local variant="$1" digest="$2" dst="$3" dir="$tmp/rusty-$1"
  local asset="rusty-psn-${variant}-linux-${rusty_arch}.zip"
  download_checked \
    "https://github.com/RainbowCookie32/rusty-psn/releases/download/${rusty_version}/${asset}" \
    "$digest" "$tmp/$asset"
  mkdir -p "$dir"
  unzip -q "$tmp/$asset" -d "$dir"
  mapfile -d '' -t binaries < <(find "$dir" -type f \( -name rusty-psn -o -name rusty-psn-cli -o -name rusty-psn-egui \) -print0)
  if (( ${#binaries[@]} != 1 )); then
    echo "ERROR: expected exactly one rusty-psn binary in $asset" >&2
    exit 1
  fi
  install -D -m 0755 "${binaries[0]}" "$dst"
}
install_rusty cli "$rusty_cli_sha" /usr/bin/rusty-psn-cli
install_rusty egui "$rusty_gui_sha" /usr/bin/rusty-psn

# 3. Gemba/Skyscraper, XDG-friendly Qt AppImage (GPL-3.0).
# Extract it at build time so it can run WITHOUT FUSE or network access on
# the immutable OS, even when /dev/fuse is unavailable.
skyscraper_version='3.21.1'
skyscraper_asset="Skyscraper-${skyscraper_version}-${skyscraper_arch}-XDG.AppImage"
download_checked \
  "https://github.com/Gemba/skyscraper/releases/download/${skyscraper_version}/${skyscraper_asset}" \
  "$skyscraper_sha" "$tmp/$skyscraper_asset"
chmod 0755 "$tmp/$skyscraper_asset"
(
  cd "$tmp"
  "./$skyscraper_asset" --appimage-extract >/dev/null
)
test -x "$tmp/squashfs-root/AppRun"
install -d /usr/libexec/retro-os
cp -a "$tmp/squashfs-root" /usr/libexec/retro-os/Skyscraper.AppDir
cat > /usr/bin/Skyscraper <<'SH'
#!/bin/sh
exec /usr/libexec/retro-os/Skyscraper.AppDir/AppRun "$@"
SH
chmod 0755 /usr/bin/Skyscraper

# Desktop entry for the GUI; the other utilities are primarily CLI tools.
install -d /usr/share/applications
cat > /usr/share/applications/astra-rusty-psn.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=rusty-psn
Comment=Download console game updates
Exec=rusty-psn
Icon=applications-games
Categories=Game;Utility;
Terminal=false
StartupNotify=true
DESKTOP

# Fail the OCI build if any of the three programs were not staged.
for executable in ps3dec rusty-psn rusty-psn-cli Skyscraper; do
  test -x "/usr/bin/$executable"
done
echo "Installed ps3dec $ps3dec_version, rusty-psn $rusty_version and Skyscraper $skyscraper_version ($arch)"
