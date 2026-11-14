#!/usr/bin/env bash
# Install an extracted Skyscraper AppImage tree in immutable /usr.
# Keep executable bits for all bundled programs (especially AppRun.wrapped),
# while avoiding ownership and SELinux labels inherited from temporary files.
set -euo pipefail

src="${1:?Pass source AppDir}"
dst="${2:?Pass destination AppDir}"
[[ -d "$src" && -x "$src/AppRun" ]] || {
  echo "ERROR: Skyscraper source AppDir or AppRun missing" >&2
  exit 1
}
[[ ! -e "$dst" && ! -L "$dst" ]] || {
  echo "ERROR: Skyscraper destination already exists: $dst" >&2
  exit 1
}

install -d -m 0755 "$(dirname "$dst")"
# Copy modes from the upstream archive: --no-preserve=mode would turn
# AppRun.wrapped and other original 0755 programs into 0644 files.
# Do NOT preserve the temporary extraction's owner or SELinux context.
cp -R --preserve=mode --no-preserve=ownership,context "$src" "$dst"
# Directories must be traversable by non-root users, and resources readable.
# Capital X keeps each original executable executable; it does not mark
# ordinary data files as commands.
chmod -R u+rwX,go+rX,go-w "$dst"

for entry in AppRun AppRun.wrapped; do
  [[ -f "$dst/$entry" ]] || {
    echo "ERROR: Skyscraper $entry missing after AppDir installation" >&2
    exit 1
  }
  chmod 0755 "$dst/$entry"
  [[ -x "$dst/$entry" ]] || {
    echo "ERROR: Skyscraper $entry is not executable after installation" >&2
    exit 1
  }
done

# The copy takes place as root in the OCI builder. Check the *final* paths as
# a normal user, including the wrapped executable that caused EACCES.
if [[ "$EUID" == 0 ]] && command -v runuser >/dev/null 2>&1; then
  for entry in AppRun AppRun.wrapped; do
    runuser -u nobody -- test -x "$dst/$entry" || {
      echo "ERROR: Skyscraper $entry inaccessible to an unprivileged user" >&2
      exit 1
    }
  done
fi
