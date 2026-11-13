#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$script_dir/sync-installed-boot.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
root="$tmp/root"
mkdir -p "$root/usr/share/astra-retro-os" "$root/usr/lib/grub/x86_64-efi" \
  "$root/boot/grub2" "$root/boot/loader/entries"
printf 'Astra image' > "$root/usr/share/astra-retro-os/grub-background.png"
printf 'GRUB module' > "$root/usr/lib/grub/x86_64-efi/gfxterm_background.mod"
cat > "$root/boot/grub2/grub.cfg" <<'GRUB'
if [ -f $prefix/user.cfg ]; then
  source $prefix/user.cfg
fi
blscfg
GRUB
cat > "$root/boot/grub2/user.cfg" <<'GRUB'
# Preserve existing user customization
set my_grub_setting=yes
GRUB
cat > "$root/boot/loader/entries/bootc_fedora-45.20261110.0-1.conf" <<'BLS'
title Astra Retro OS
version 45.20261110.0
linux /ostree/astra/vmlinuz
initrd /ostree/astra/initramfs.img
options root=UUID=aabb ro ostree=/ostree/boot.1/astra/a/0 quiet rhgb $kernelopts
BLS

ASTRA_ROOT="$root" "$script"
usercfg="$root/boot/grub2/user.cfg"
debug="$root/boot/loader/entries/0000-astra-retro-debug-0.conf"
test -s "$root/boot/grub2/astra-background.png"
test -s "$root/boot/grub2/x86_64-efi/gfxterm_background.mod"
grep -Fq 'set my_grub_setting=yes' "$usercfg"
grep -Fq 'background_image -m stretch' "$usercfg"
# Installed GRUB must mirror the interruptible Live splash/menu handling.
grep -Fq 'if sleep --interruptible 5; then' "$usercfg"
grep -Fq 'set timeout_style=menu' "$usercfg"
grep -Fq 'set timeout=0' "$usercfg"
grep -Fq 'set timeout=-1' "$usercfg"
grep -Fq 'set astra_background_ok=0' "$usercfg"
grep -Fq 'set astra_background_ok=1' "$usercfg"
grep -Fq 'set timeout=10' "$usercfg"
! grep -Fq 'set timeout_style=hidden' "$usercfg"
# The live ISO already uses this same interruptible 5-second wait.
grep -Fq 'sleep --interruptible 5' "$script_dir/../installer/titanoboa/build_iso_branded.sh"
grep -Fq 'ostree=/ostree/boot.1/astra/a/0' "$debug"
grep -Fq 'plymouth.enable=0' "$debug"
! grep -Eq '(^| )quiet( |$)' "$debug"
! grep -Eq '(^| )rhgb( |$)' "$debug"
[[ $(grep -c 'BEGIN ASTRA RETRO OS' "$usercfg") == 1 ]]
sha_user="$(sha256sum "$usercfg" | cut -d' ' -f1)"
sha_debug="$(sha256sum "$debug" | cut -d' ' -f1)"
ASTRA_ROOT="$root" "$script"
[[ "$(sha256sum "$usercfg" | cut -d' ' -f1)" == "$sha_user" ]]
[[ "$(sha256sum "$debug" | cut -d' ' -f1)" == "$sha_debug" ]]
# When bootc stages a new normal BLS entry, the debug entry must track it.
cat > "$root/boot/loader/entries/bootc_fedora-45.20261111.0-1.conf" <<'BLS'
title Astra Retro OS (new)
version 45.20261111.0
linux /ostree/new/vmlinuz
initrd /ostree/new/initramfs.img
options root=UUID=ccdd ro ostree=/ostree/boot.1/astra/b/0 quiet rhgb
BLS
ASTRA_ROOT="$root" "$script"
grep -Fq 'ostree=/ostree/boot.1/astra/b/0' "$debug"
! grep -Fq 'ostree=/ostree/boot.1/astra/a/0' "$debug"

# Simulate Fedora bootc's read-only /boot mount without requiring a
# privileged runner. Mock only mount inspection and remount operations.
mkdir -p "$tmp/mount-mocks"
printf 'ro\n' > "$tmp/mount-state"
: > "$tmp/remount-log"
cat > "$tmp/mount-mocks/findmnt" <<'MOCK'
#!/usr/bin/env bash
cat "$ASTRA_MOUNT_STATE"
MOCK
cat > "$tmp/mount-mocks/mountpoint" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "-q" && "$2" == "$ASTRA_EXPECTED_BOOT" ]]
MOCK
cat > "$tmp/mount-mocks/mount" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "--options-source=disable" && "$2" == "-o" ]] || exit 1
case "$3" in
  remount,rw) printf 'rw\n' > "$ASTRA_MOUNT_STATE" ;;
  remount,ro) printf 'ro\n' > "$ASTRA_MOUNT_STATE" ;;
  *) exit 1 ;;
esac
printf '%s %s\n' "$3" "$4" >> "$ASTRA_REMOUNT_LOG"
MOCK
chmod +x "$tmp/mount-mocks/"*
ASTRA_MOUNT_STATE="$tmp/mount-state" \
ASTRA_REMOUNT_LOG="$tmp/remount-log" \
ASTRA_EXPECTED_BOOT="$root/boot" \
PATH="$tmp/mount-mocks:$PATH" ASTRA_ROOT="$root" "$script"
[[ "$(cat "$tmp/mount-state")" == ro ]]
[[ "$(wc -l < "$tmp/remount-log")" == 2 ]]
grep -Fq "remount,rw $root/boot" "$tmp/remount-log"
grep -Fq "remount,ro $root/boot" "$tmp/remount-log"

# The sleep module must be loaded while the prefix points at /boot/grub2,
# not after restoring the Fedora EFI module path.
python3 - "$script" <<'PY'
import sys
from pathlib import Path
source = Path(sys.argv[1]).read_text()
branding = source.split("cat >> \"$tmp\" <<'GRUB'", 1)[1].split("\nGRUB\n", 1)[0]
assert branding.index("if insmod sleep; then") < branding.index("set prefix=$astra_previous_prefix")
assert 'if [ "${astra_sleep_available}" = 1 ]; then' in branding
PY

# bootupd may use custom.cfg, with the source on the same line as a guard.
cat > "$root/boot/grub2/grub.cfg" <<'GRUB'
if [ -f $prefix/custom.cfg ]; then source $prefix/custom.cfg; fi
blscfg
GRUB
rm -f "$root/boot/grub2/user.cfg"
ASTRA_ROOT="$root" "$script"
grep -Fq 'BEGIN ASTRA RETRO OS INSTALLED BRANDING' "$root/boot/grub2/custom.cfg"
grep -Fq 'background_image -m stretch' "$root/boot/grub2/custom.cfg"
# Reruns are idempotent for bootupd's custom.cfg variant.
sha_custom="$(sha256sum "$root/boot/grub2/custom.cfg" | cut -d' ' -f1)"
ASTRA_ROOT="$root" "$script"
[[ "$(sha256sum "$root/boot/grub2/custom.cfg" | cut -d' ' -f1)" == "$sha_custom" ]]

# bootupd static GRUB loads console.cfg before blscfg. Prefer it to the
# late custom.cfg hook, and migrate the previous Astra section without touching
# the user's own GRUB configuration.
cat > "$root/boot/grub2/grub.cfg" <<'GRUB'
if [ -f $prefix/console.cfg ]; then
  source $prefix/console.cfg
fi
blscfg
if [ -f $prefix/custom.cfg ]; then
  source $prefix/custom.cfg
fi
GRUB
cat > "$root/boot/grub2/console.cfg" <<'GRUB'
# User console customization
set user_console_option=yes
GRUB
ASTRA_ROOT="$root" "$script"
consolecfg="$root/boot/grub2/console.cfg"
grep -Fq 'set user_console_option=yes' "$consolecfg"
grep -Fq 'background_image -m stretch' "$consolecfg"
! grep -Fq 'BEGIN ASTRA RETRO OS INSTALLED BRANDING' "$root/boot/grub2/custom.cfg"
sha_console="$(sha256sum "$consolecfg" | cut -d' ' -f1)"
ASTRA_ROOT="$root" "$script"
[[ "$(sha256sum "$consolecfg" | cut -d' ' -f1)" == "$sha_console" ]]
# A stale old fragment must not be kept in a different GRUB hook.
grep -Fq 'set my_grub_setting=yes' "$root/boot/grub2/console.cfg" && exit 1
# Reapplying with an inline console hook must remain supported.
printf 'if [ -f $prefix/console.cfg ]; then source $prefix/console.cfg; fi\nblscfg\n' > "$root/boot/grub2/grub.cfg"
ASTRA_ROOT="$root" "$script"
[[ "$(sha256sum "$consolecfg" | cut -d' ' -f1)" == "$sha_console" ]]

# Commented-out hooks must never be mistaken for a real GRUB inclusion.
printf '# source $prefix/custom.cfg\nblscfg\n' > "$root/boot/grub2/grub.cfg"
rm -f "$root/boot/grub2/custom.cfg"
if ASTRA_ROOT="$root" "$script"; then
  echo 'ERROR: accepted a commented-out GRUB hook' >&2
  exit 1
fi
[[ ! -f "$root/boot/grub2/custom.cfg" ]]

# An unknown GRUB layout must be left untouched, not rewritten.
printf 'blscfg\n' > "$root/boot/grub2/grub.cfg"
rm -f "$usercfg"
if ASTRA_ROOT="$root" "$script"; then
  echo 'ERROR: accepted an unsupported GRUB layout' >&2
  exit 1
fi
[[ ! -f "$usercfg" ]]
echo 'Installed GRUB branding tests passed'
