#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash -n build_files/build.sh build_files/05-retro-emulation.sh build_files/06-finalize.sh build_files/tools/install-retro-utilities.sh
python3 - <<'PY'
from pathlib import Path
source = Path('build_files/build.sh').read_text()
assert source.index('/ctx/04-install-packages.sh') < source.index('/ctx/05-retro-emulation.sh') < source.index('/ctx/06-finalize.sh')
assert source.index('/ctx/06-finalize.sh') < source.index('/tmp/system_files/overrides/*')

emulation = Path('build_files/05-retro-emulation.sh').read_text()
assert emulation.index('cp --archive --verbose --force /tmp/system_files/retro-emulation/usr/. /usr/') < emulation.index('for tool in retro-emulation-setup')
assert 'test -s /usr/share/retro-os/esde/splash.svg' in emulation
assert 'bash /ctx/tools/install-retro-utilities.sh' in emulation
installer = Path('build_files/tools/install-retro-utilities.sh').read_text()
assert 'sha256sum -c -' in installer
for project in ('Redrrx/ps3dec', 'RainbowCookie32/rusty-psn', 'Gemba/skyscraper'):
    assert project in installer
for cmd in ('/usr/bin/ps3dec', '/usr/bin/rusty-psn-cli', '/usr/bin/rusty-psn', '/usr/bin/Skyscraper'):
    assert cmd in installer
# The AppRun path is now assembled from $appdir, rather than a single
# literal string: keep the test aligned with the real installation.
assert 'appdir=/usr/libexec/retro-os/Skyscraper.AppDir' in installer
assert 'test -x "$appdir/AppRun"' in installer
assert 'exec "$APPDIR/AppRun" "$@"' in installer
assert '--appimage-extract' in installer
# Extracted AppImages must be copied without restrictive permissions or
# temporary SELinux contexts, then verified as an unprivileged user.
assert 'cp -a "$tmp/squashfs-root"' not in installer
assert 'cp -R --no-preserve=mode,ownership,context' in installer
assert 'chmod -R u+rwX,go+rX,go-w "$appdir"' in installer
assert 'chmod 0755 "$appdir/AppRun"' in installer
assert 'runuser -u nobody -- test -x "$appdir/AppRun"' in installer
assert 'APPDIR=/usr/libexec/retro-os/Skyscraper.AppDir' in installer

# Find predicate parentheses must be escaped exactly once in the shell.
# A duplicate backslash caused the parser failure reported in CI.
slash = chr(92)
assert (slash + '( -name rusty-psn') in installer
assert ('-name rusty-psn-egui ' + slash + ')') in installer
assert (slash * 2 + '( -name rusty-psn') not in installer
assert ('-name rusty-psn-egui ' + slash * 2 + ')') not in installer

helper_dir = Path('system_files/retro-emulation/usr/libexec/retro-os')
for name in ('retro-emulation-setup', 'retro-fetch-esde', 'retro-launch-esde', 'retro-install-emudeck', 'retro-configure-esde'):
    path = helper_dir / name
    assert path.is_file() and path.stat().st_size, str(path)
assert Path('system_files/retro-emulation/usr/lib/systemd/user/retro-emulation-setup.service').is_file()
assert Path('system_files/retro-emulation/usr/share/retro-os/esde/splash.svg').is_file()
PY
echo 'Retro emulation install-order checks passed'
