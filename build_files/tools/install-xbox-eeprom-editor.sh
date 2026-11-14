#!/usr/bin/env bash
# Install the pinned upstream Windows/.NET release for use with Mono.
# This is a build-time download; the installed immutable OS never fetches it.
set -euo pipefail

version='1.0.0.1'
asset="XboxEepromEditor.${version}.zip"
url="https://github.com/Ernegien/XboxEepromEditor/releases/download/${version}/${asset}"
# Upstream does not publish a SHA-256 digest for this release. Pin its exact
# release URL and 128970-byte asset length, and verify the ZIP CRC plus payload.
# Print the SHA-256 in build logs for auditing/reproducibility.
expected_bytes=128970

for command in curl unzip stat find sha256sum install mono; do
    command -v "$command" >/dev/null || {
        echo "ERROR: missing required build tool: $command" >&2
        exit 1
    }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/$asset"
curl --fail --location --retry 4 --retry-all-errors --silent --show-error \
    --output "$archive" "$url"
actual_bytes="$(stat -c %s "$archive")"
if [[ "$actual_bytes" != "$expected_bytes" ]]; then
    echo "ERROR: $asset has unexpected size: $actual_bytes (expected $expected_bytes)" >&2
    exit 1
fi
unzip -tq "$archive" >/dev/null
echo "XboxEepromEditor upstream asset SHA-256: $(sha256sum "$archive")"

mkdir -p "$tmp/extracted"
unzip -q "$archive" -d "$tmp/extracted"
mapfile -d '' -t executables < <(find "$tmp/extracted" -type f -name 'XboxEepromEditor.exe' -print0)
if (( ${#executables[@]} != 1 )); then
    echo "ERROR: expected exactly one XboxEepromEditor.exe in $asset" >&2
    exit 1
fi

# Preserve any adjacent .dll/.config files: Serilog is required at startup.
source_dir="$(dirname "${executables[0]}")"
for library in Serilog.dll Serilog.Sinks.File.dll; do
    if [[ ! -s "$source_dir/$library" ]]; then
        echo "ERROR: missing $library beside XboxEepromEditor.exe" >&2
        exit 1
    fi
done

dest=/usr/libexec/retro-os/XboxEepromEditor
install -d -m 0755 "$dest"
cp -R --preserve=mode --no-preserve=ownership,context "$source_dir/." "$dest/"
find "$dest" -type d -exec chmod 0755 {} +
find "$dest" -type f -exec chmod 0644 {} +
test -s "$dest/XboxEepromEditor.exe"

# The editor writes XboxEepromEditor.log to its working directory.
# Keep mutable logs in the user's XDG state directory, never in /usr.
cat > /usr/bin/xbox-eeprom-editor <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
install -d -m 0700 "$state_home/xbox-eeprom-editor"
cd "$state_home/xbox-eeprom-editor"
exec /usr/bin/mono /usr/libexec/retro-os/XboxEepromEditor/XboxEepromEditor.exe "$@"
LAUNCHER
chmod 0755 /usr/bin/xbox-eeprom-editor

install -d -m 0755 /usr/share/applications
cat > /usr/share/applications/astra-xbox-eeprom-editor.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Xbox EEPROM Editor
Comment=Edit and generate Original Xbox EEPROM images
Exec=xbox-eeprom-editor
Icon=applications-games
Categories=Game;Utility;
Terminal=false
StartupNotify=true
DESKTOP

test -x /usr/bin/xbox-eeprom-editor
test -s /usr/share/applications/astra-xbox-eeprom-editor.desktop
echo "Installed XboxEepromEditor $version for Mono"
