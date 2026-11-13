#!/usr/bin/env bash
# Regression: the extracted linuxdeploy AppRun chain must run as non-root.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
helper="$PWD/build_files/tools/install-extracted-appdir.sh"
bash -n "$helper"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod 0755 "$tmp"
mkdir -p "$tmp/source/usr/bin"
cat > "$tmp/source/AppRun" <<'SH'
#!/bin/sh
exec "$(dirname "$0")/AppRun.wrapped" "$@"
SH
cat > "$tmp/source/AppRun.wrapped" <<'SH'
#!/bin/sh
printf 'Skyscraper mock started\n'
SH
cat > "$tmp/source/usr/bin/program" <<'SH'
#!/bin/sh
exit 0
SH
echo 'resource' > "$tmp/source/usr/bin/data.txt"
chmod 0755 "$tmp/source/AppRun" "$tmp/source/AppRun.wrapped" "$tmp/source/usr/bin/program"
chmod 0644 "$tmp/source/usr/bin/data.txt"
bash "$helper" "$tmp/source" "$tmp/dest/Skyscraper.AppDir"
test -x "$tmp/dest/Skyscraper.AppDir/AppRun"
test -x "$tmp/dest/Skyscraper.AppDir/AppRun.wrapped"
test -x "$tmp/dest/Skyscraper.AppDir/usr/bin/program"
test ! -x "$tmp/dest/Skyscraper.AppDir/usr/bin/data.txt"
test "$("$tmp/dest/Skyscraper.AppDir/AppRun")" = 'Skyscraper mock started'
if [[ "$EUID" == 0 ]] && command -v runuser >/dev/null 2>&1; then
  test "$(runuser -u nobody -- "$tmp/dest/Skyscraper.AppDir/AppRun")" = 'Skyscraper mock started'
fi
echo 'Skyscraper AppRun.wrapped executable-mode regression test passed'
