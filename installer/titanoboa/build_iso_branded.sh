#!/usr/bin/env bash
# Astra Retro OS Live ISO builder, based on Titanoboa's build_iso.sh.
# Upstream: https://github.com/ublue-os/titanoboa/blob/main/build_iso.sh
# License: Apache-2.0 (upstream Titanoboa)
#
# The stock Titanoboa action creates a menu but does not embed GRUB branding.
# This variant puts the image and grub.cfg in BOTH the ISO tree and the FAT EFI
# boot image, so GRUB can access the background before the Linux LiveOS mounts.
set -euo pipefail

dnf5 install -qy squashfs-tools xorriso yq mtools dosfstools

mkdir -p /work/iso-root/boot/grub2 /work/iso-root/images/pxeboot /work/iso-root/LiveOS
cd /work

mksquashfs /rootfs /work/iso-root/LiveOS/squashfs.img \
  -all-root -noappend -e sysroot -e ostree -comp zstd -Xcompression-level 19

config=/rootfs/usr/lib/bootc-image-builder/iso.yaml
background=/src/grub-background.png
[[ -s "$config" ]] || { echo "Missing Titanoboa config: $config" >&2; exit 1; }
[[ -s "$background" ]] || { echo "Missing GRUB background: $background" >&2; exit 1; }
iso_label=$(yq '.label' < "$config")
[[ -n "$iso_label" && "$iso_label" != "null" ]] || { echo 'Invalid ISO label' >&2; exit 1; }

cp -av /rootfs/usr/lib/modules/*/initramfs.img /work/iso-root/images/pxeboot/initrd.img
cp -av /rootfs/usr/lib/modules/*/vmlinuz /work/iso-root/images/pxeboot/vmlinuz

# Preserve upstream Titanoboa's boot modules and EFI binaries.
for arch in i386-pc arm64-efi; do
  if [[ -d "/rootfs/usr/lib/grub/$arch" ]]; then
    mkdir -p "/work/iso-root/boot/grub2/$arch"
    cp -avT "/rootfs/usr/lib/grub/$arch" "/work/iso-root/boot/grub2/$arch"
  fi
done
cp -avT /rootfs/boot/efi/EFI /work/EFI

# Put the image directly on the ISO and the EFI partition. A PNG inside
# /LiveOS/squashfs.img or /usr/share is NOT accessible to GRUB at this stage.
install -Dm0644 "$background" /work/iso-root/boot/grub2/astra-background.png
for dir in /work/EFI/*; do
  [[ -d "$dir" ]] || continue
  install -m 0644 "$background" "$dir/astra-background.png"
done

# gfxterm needs a font on many GRUB builds.
for source in \
  /rootfs/usr/share/grub/unicode.pf2 \
  /rootfs/boot/grub2/fonts/unicode.pf2 \
  /usr/share/grub/unicode.pf2; do
  if [[ -s "$source" ]]; then
    install -Dm0644 "$source" /work/iso-root/boot/grub2/fonts/unicode.pf2
    break
  fi
done

grub_cfg="$(cat <<EOF
set timeout=$(yq '.grub2.timeout // 10' < "$config")
set default=$(yq '.grub2.default // 0' < "$config")
set menu_auto_hide=false
insmod all_video
insmod gfxterm
insmod gfxterm_background
insmod png
set gfxmode=auto
if [ -f /boot/grub2/fonts/unicode.pf2 ]; then
  loadfont /boot/grub2/fonts/unicode.pf2
fi
terminal_output gfxterm
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod chain
search --no-floppy --set=root -l '$iso_label'
if background_image -m stretch /boot/grub2/astra-background.png; then
  set color_normal=white/black
  set color_highlight=black/light-cyan
  set menu_color_normal=white/black
  set menu_color_highlight=black/light-cyan
else
  echo 'Astra Retro OS: GRUB background unavailable; continuing with text menu.'
fi
EOF
)"

for i in $(yq '.grub2.entries | keys | .[]' < "$config"); do
  entry_name=$(yq ".grub2.entries[$i].name" < "$config")
  entry_linux=$(yq ".grub2.entries[$i].linux" < "$config")
  entry_initrd=$(yq ".grub2.entries[$i].initrd" < "$config")
  grub_cfg+=$'\n'"menuentry '$entry_name' {"
  grub_cfg+=$'\n'"  linux $entry_linux"
  grub_cfg+=$'\n'"  initrd $entry_initrd"
  grub_cfg+=$'\n}'
done

# Titanoboa's GRUB binaries look for grub.cfg in different locations depending
# on whether the media is booted through ISO or UEFI.
for dir in /work/EFI/* /work/iso-root/boot/grub2; do
  [[ -d "$dir" ]] || continue
  printf '%s\n' "$grub_cfg" > "$dir/grub.cfg"
done
cp -avT /work/EFI /work/iso-root/EFI

truncate -s 100M /work/uefi.img
mkfs.fat -F32 /work/uefi.img
mcopy -v -i /work/uefi.img -s /work/EFI ::

# Fail early if the expected files are not in the EFI FAT filesystem.
mdir -i /work/uefi.img ::/EFI/BOOT/astra-background.png
mdir -i /work/uefi.img ::/EFI/BOOT/grub.cfg

a=$(test -s /work/iso-root/boot/grub2/astra-background.png && echo yes)
[[ "$a" == yes ]]
grep -q 'background_image.*astra-background.png' /work/iso-root/boot/grub2/grub.cfg

xorriso -as mkisofs \
  -R \
  -V "$iso_label" \
  -partition_offset 16 \
  -appended_part_as_gpt \
  -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B ./uefi.img \
  -iso_mbr_part_type EBD0A0A2-B9E5-4433-87C0-68B6B72699C7 \
  -e --interval:appended_partition_2:all:: \
  -no-emul-boot \
  -iso-level 3 \
  -o "/output/${iso_label}.iso" \
  iso-root
