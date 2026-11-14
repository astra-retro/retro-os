#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash -n build_files/build.sh build_files/05-retro-emulation.sh build_files/06-finalize.sh build_files/tools/install-retro-utilities.sh build_files/tools/install-extracted-appdir.sh build_files/tools/install-xbox-eeprom-editor.sh
python3 - <<'PY'
from pathlib import Path
source = Path('build_files/build.sh').read_text()
assert source.index('/ctx/04-install-packages.sh') < source.index('/ctx/05-retro-emulation.sh') < source.index('/ctx/06-finalize.sh')
assert source.index('/ctx/06-finalize.sh') < source.index('/tmp/system_files/overrides/*')

emulation = Path('build_files/05-retro-emulation.sh').read_text()
assert emulation.index('cp --archive --verbose --force /tmp/system_files/retro-emulation/usr/. /usr/') < emulation.index('for tool in retro-emulation-setup')
assert 'test -s /usr/share/retro-os/esde/splash.svg' in emulation
assert 'bash /ctx/tools/install-retro-utilities.sh' in emulation
assert 'bash /ctx/tools/install-xbox-eeprom-editor.sh' in emulation
# Check the PS3 ISO tools are built reproducibly and copied into immutable
# /usr without adding a compiler to the running OS image.
containerfile = Path('Containerfile').read_text()
assert 'FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS ps3iso-utils-builder' in containerfile
assert 'ARG PS3ISO_UTILS_COMMIT=878090980a9042c61901920fed1b034af215e8c7' in containerfile
assert 'git -C /tmp/ps3iso-utils checkout --quiet --detach "${PS3ISO_UTILS_COMMIT}"' in containerfile
assert 'git -C /tmp/ps3iso-utils rev-parse HEAD' in containerfile
assert 'for tool in extractps3iso makeps3iso patchps3iso splitps3iso; do' in containerfile
assert 'make -C "/tmp/ps3iso-utils/${tool}"' in containerfile
assert 'install -D -m 0755 "/tmp/ps3iso-utils/${tool}/${tool}" "/out/bin/${tool}"' in containerfile
assert 'COPY --from=ps3iso-utils-builder /out/bin/ /usr/bin/' in containerfile
assert 'COPY --from=ps3iso-utils-builder /out/share/licenses/ps3iso-utils/ /usr/share/licenses/ps3iso-utils/' in containerfile
assert containerfile.index('COPY --from=ps3iso-utils-builder /out/bin/') < containerfile.index('bootc container lint')
assert Path('docs/ps3iso-utils.md').is_file()
packages = Path('build_files/04-install-packages.sh').read_text()
for package in ('mono-core', 'mono-winforms', 'xorriso'):
    assert ('    ' + package + ' '+chr(92)) in packages
xbox = Path('build_files/tools/install-xbox-eeprom-editor.sh').read_text()
assert "version='1.0.0.1'" in xbox
assert 'unzip -tq "$archive"' in xbox
assert 'exec /usr/bin/mono /usr/libexec/retro-os/XboxEepromEditor/XboxEepromEditor.exe' in xbox
assert 'state_home="${XDG_STATE_HOME:-$HOME/.local/state}"' in xbox
assert 'astra-xbox-eeprom-editor.desktop' in xbox
installer = Path('build_files/tools/install-retro-utilities.sh').read_text()
assert 'sha256sum -c -' in installer
for project in ('Redrrx/ps3dec', 'RainbowCookie32/rusty-psn', 'Gemba/skyscraper'):
    assert project in installer
for cmd in ('/usr/bin/ps3dec', '/usr/bin/rusty-psn-cli', '/usr/bin/rusty-psn', '/usr/bin/Skyscraper'):
    assert cmd in installer
# The staging script delegates all AppDir permission validation to the
# helper. Do not assert a literal validation command in this caller:
# its implementation and variable names belong to the helper instead.
assert 'appdir=/usr/libexec/retro-os/Skyscraper.AppDir' in installer
assert 'exec "$APPDIR/AppRun" "$@"' in installer
assert '--appimage-extract' in installer
# Verify the installed AppDir helper is used. It must preserve upstream
# executable modes while dropping temporary owner/SELinux contexts.
helper_script = Path('build_files/tools/install-extracted-appdir.sh')
assert helper_script.is_file()
helper = helper_script.read_text()
assert 'bash /ctx/tools/install-extracted-appdir.sh "$tmp/squashfs-root" "$appdir"' in installer
assert 'cp -R --preserve=mode --no-preserve=ownership,context' in helper
assert 'AppRun.wrapped' in helper
assert 'for entry in AppRun AppRun.wrapped; do' in helper
assert '[[ -x "$dst/$entry" ]]' in helper
assert 'runuser -u nobody -- test -x "$dst/$entry"' in helper
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
bash build_files/test-skyscraper-appdir.sh
# Regression for GitHub runners: ensure this test also resolves its helper
# correctly when invoked from outside the repository working directory.
repo_root="$PWD"
(
  cd /tmp
  bash "$repo_root/build_files/test-skyscraper-appdir.sh"
)
echo 'Retro emulation install-order checks passed'
