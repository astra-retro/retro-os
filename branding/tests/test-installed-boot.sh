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

# An unknown GRUB layout must be left untouched, not rewritten.
printf 'blscfg\n' > "$root/boot/grub2/grub.cfg"
rm -f "$usercfg"
ASTRA_ROOT="$root" "$script"
[[ ! -f "$usercfg" ]]
echo 'Installed GRUB branding tests passed'
