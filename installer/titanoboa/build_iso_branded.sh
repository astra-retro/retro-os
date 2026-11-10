#!/usr/bin/env bash
# Astra Retro OS Live ISO builder, based on Titanoboa's build_iso.sh.
# Upstream: https://github.com/ublue-os/titanoboa/blob/main/build_iso.sh
# License: Apache-2.0 (upstream Titanoboa)
#
# The stock Titanoboa action creates a menu but does not embed GRUB branding.
# This variant puts the image and grub.cfg in BOTH the ISO tree and the FAT EFI
# boot image, so GRUB can access the background before the Linux LiveOS mounts.
set -euo pipefail

dnf5 install -qy squashfs-tools xorriso yq mtools dosfstools util-linux \
  grub2-efi-x64-modules grub2-tools-extra dejavu-sans-fonts

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

# Keep the upstream EFI boot binaries; make external GRUB modules available
# from both the ISO filesystem and the EFI system partition. This fixes missing
# gfxterm_background/png modules on UEFI installations where GRUB loads from FAT.
for arch in i386-pc arm64-efi x86_64-efi; do
  source_modules="/rootfs/usr/lib/grub/$arch"
  if [[ ! -d "$source_modules" && -d "/usr/lib/grub/$arch" ]]; then
    source_modules="/usr/lib/grub/$arch"
  fi
  if [[ -d "$source_modules" ]]; then
    install -d "/work/iso-root/boot/grub2/$arch"
    cp -a "$source_modules/." "/work/iso-root/boot/grub2/$arch/"
  fi
done
cp -avT /rootfs/boot/efi/EFI /work/EFI

# The EFI binary normally uses EFI/BOOT as $prefix. Its modules need to be
# accessible at EFI/BOOT/x86_64-efi in addition to the ISO GRUB directory.
if [[ -d /work/iso-root/boot/grub2/x86_64-efi ]]; then
  install -d /work/EFI/BOOT/x86_64-efi
  cp -a /work/iso-root/boot/grub2/x86_64-efi/. /work/EFI/BOOT/x86_64-efi/
fi

# GRUB may keep $root on the EFI FAT partition or switch it to the ISO.
# Provide the background at the SAME absolute path in both filesystems.
# The ISO copy below is made when /work/EFI is copied to /work/iso-root/EFI.
install -Dm0644 "$background" /work/iso-root/boot/grub2/astra-background.png
install -Dm0644 "$background" /work/EFI/BOOT/astra-background.png

# Without a GRUB PF2 font, graphical borders can appear as rectangles
# filled with '?' characters. The previous builder loaded the font BEFORE
# `search --set=root` and never copied it into the EFI FAT image.
font_dest=/work/iso-root/boot/grub2/fonts/unicode.pf2
install -d "$(dirname "$font_dest")"
for source_font in \
  /rootfs/usr/share/grub/unicode.pf2 \
  /rootfs/usr/share/grub2/unicode.pf2 \
  /rootfs/boot/grub2/fonts/unicode.pf2 \
  /usr/share/grub/unicode.pf2 \
  /usr/share/grub2/unicode.pf2; do
  if [[ -s "$source_font" ]]; then
    install -m 0644 "$source_font" "$font_dest"
    break
  fi
done
if [[ ! -s "$font_dest" ]]; then
  font_ttf=$(find /usr/share/fonts -type f \
    \( -name DejaVuSans.ttf -o -name NotoSans-Regular.ttf \) \
    -print -quit)
  [[ -n "$font_ttf" ]] || {
    echo 'No GRUB PF2 font or TTF fallback available' >&2
    exit 1
  }
  grub2-mkfont -s 18 -o "$font_dest" "$font_ttf"
fi
[[ -s "$font_dest" ]] || { echo 'GRUB font is missing' >&2; exit 1; }
install -Dm0644 "$font_dest" /work/EFI/BOOT/fonts/unicode.pf2

grub_cfg="$(cat <<EOF
# Select the ISO filesystem FIRST. The original configuration attempted to
# load a font while GRUB was still rooted at the EFI system partition.
search --no-floppy --set=root -l '$iso_label'
set default=$(yq '.grub2.default // 0' < "$config")
set menu_auto_hide=false

# Prefer the font embedded in a signed GRUB image (Secure Boot), otherwise
# load our validated font from the Live ISO. Never rely on a missing font.
if loadfont unicode; then
  set astra_font_loaded=1
else
  if loadfont /boot/grub2/fonts/unicode.pf2; then
    set astra_font_loaded=1
  fi
fi

insmod all_video
insmod gfxterm
insmod gfxterm_background
insmod png
set gfxmode=auto
terminal_output gfxterm
set gfxpayload=keep
insmod gzio
insmod part_gpt
insmod chain
set color_normal=white/black
set color_highlight=black/light-cyan
set menu_color_normal=white/black
set menu_color_highlight=black/light-cyan

# Explicitly draw the splash *before* the boot timeout. GRUB's default hidden
# timeout can clear the graphical screen on some EFI firmwares; an interruptible
# sleep keeps the picture displayed and switches to an indefinite menu on ESC.
# Both the ISO and the EFI FAT partition contain this exact path. The
# older /boot/grub2 path existed ONLY on the ISO, not on the EFI partition.
if background_image -m stretch /EFI/BOOT/astra-background.png; then
  if insmod sleep; then
    if sleep --interruptible 5; then
      set timeout=0
    else
      set timeout=-1
    fi
  else
    # A GRUB build lacking the sleep module still supports hidden timeouts.
    set timeout_style=hidden
    set timeout=5
  fi
else
  # Keep the system bootable and show the normal menu if graphics fail.
  echo 'Astra Retro OS: GRUB background unavailable; showing boot menu.'
  set timeout=5
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

# Stage the exact path used by grub.cfg explicitly in the ISO9660 tree,
# independently of the EFI-directory tree copy above.
install -Dm0644 "$background" /work/iso-root/EFI/BOOT/astra-background.png
cmp "$background" /work/iso-root/EFI/BOOT/astra-background.png

truncate -s 100M /work/uefi.img
mkfs.fat -F32 /work/uefi.img
mcopy -v -i /work/uefi.img -s /work/EFI ::

# Explicitly update the image at GRUB's expected path INSIDE the FAT EFI
# filesystem, not only in the ISO9660 tree. mcopy -o avoids an interactive
# overwrite prompt if the recursive EFI copy already created that file.
mcopy -o -i /work/uefi.img "$background" ::/EFI/BOOT/astra-background.png

# Verify the actual FAT file contents rather than merely checking its name.
fat_verify_dir=$(mktemp -d)
mcopy -i /work/uefi.img ::/EFI/BOOT/astra-background.png \
  "$fat_verify_dir/astra-background.png"
if ! cmp -s "$background" "$fat_verify_dir/astra-background.png"; then
  echo 'ERROR: EFI FAT image contains an incorrect GRUB background' >&2
  exit 1
fi
rm -rf "$fat_verify_dir"

# Fail early if the expected files are not in the EFI FAT filesystem.
mdir -i /work/uefi.img ::/EFI/BOOT/astra-background.png
mdir -i /work/uefi.img ::/EFI/BOOT/grub.cfg
# Verify that the ISO and EFI filesystem copies are identical to the source.
cmp -s "$background" /work/iso-root/boot/grub2/astra-background.png
cmp -s "$background" /work/iso-root/EFI/BOOT/astra-background.png
cmp -s "$background" /work/EFI/BOOT/astra-background.png
mdir -i /work/uefi.img ::/EFI/BOOT/fonts/unicode.pf2
mdir -i /work/uefi.img ::/EFI/BOOT/x86_64-efi/gfxterm_background.mod
mdir -i /work/uefi.img ::/EFI/BOOT/x86_64-efi/png.mod

a=$(test -s /work/iso-root/boot/grub2/astra-background.png && echo yes)
[[ "$a" == yes ]]
grep -Fq 'background_image -m stretch /EFI/BOOT/astra-background.png' /work/iso-root/boot/grub2/grub.cfg

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

# Validate the *final ISO artifact*. Staging checks alone cannot detect a
# missing file if a different tree or a later repacking step produced the ISO.
iso_output="/output/${iso_label}.iso"
verify_dir=$(mktemp -d)
trap 'rm -rf "$verify_dir"' EXIT
if ! xorriso -osirrox on -indev "$iso_output" \
    -extract /EFI/BOOT/astra-background.png "$verify_dir/astra-background.png"; then
  echo "ERROR: $iso_output does not contain /EFI/BOOT/astra-background.png" >&2
  exit 1
fi
if ! cmp -s "$background" "$verify_dir/astra-background.png"; then
  echo 'ERROR: Final ISO GRUB background differs from branding source' >&2
  exit 1
fi
echo 'OK: GRUB background found and verified inside the final ISO9660 filesystem.'

# The ISO9660 files are NOT the EFI System Partition. xorriso appended the
# prepared FAT filesystem as partition 2. Extract THAT partition from the
# distributable ISO and compare the wallpaper inside it against the source.
# partx reads the partition table without loop devices or privileged mounts.
command -v partx >/dev/null || {
  echo 'ERROR: partx (util-linux) is needed to verify the final EFI partition' >&2
  exit 1
}
if ! efi_range=$(partx --show --raw --noheadings --nr 2 \
    --output START,SECTORS "$iso_output"); then
  echo "ERROR: cannot locate EFI partition 2 in $iso_output" >&2
  exit 1
fi
read -r efi_start efi_sectors <<< "$efi_range"
if [[ ! "$efi_start" =~ ^[0-9]+$ || ! "$efi_sectors" =~ ^[0-9]+$ ]] \
    || (( efi_sectors == 0 )); then
  echo "ERROR: invalid EFI partition offsets: $efi_range" >&2
  exit 1
fi

dd if="$iso_output" of="$verify_dir/final-efi.img" bs=512 \
  skip="$efi_start" count="$efi_sectors" status=none
if ! mdir -i "$verify_dir/final-efi.img" ::/EFI/BOOT/astra-background.png; then
  echo 'ERROR: background missing from FINAL ISO EFI partition' >&2
  exit 1
fi
if ! mcopy -i "$verify_dir/final-efi.img" \
    ::/EFI/BOOT/astra-background.png \
    "$verify_dir/astra-background-efi.png"; then
  echo 'ERROR: cannot extract wallpaper from FINAL ISO EFI partition' >&2
  exit 1
fi
if ! cmp -s "$background" "$verify_dir/astra-background-efi.png"; then
  echo 'ERROR: background in FINAL ISO EFI partition differs from source' >&2
  exit 1
fi
if ! mdir -i "$verify_dir/final-efi.img" ::/EFI/BOOT/grub.cfg; then
  echo 'ERROR: grub.cfg missing from FINAL ISO EFI partition' >&2
  exit 1
fi
echo 'OK: GRUB background and grub.cfg verified inside final EFI partition.'
