#!/usr/bin/env bash
# Synchronise the installed boot loader with the artwork already used in Live.
# Do NOT regenerate grub.cfg or touch the EFI vendor stub: bootupd owns them.
set -euo pipefail

root="${ASTRA_ROOT:-}"
root="${root%/}"
at() { printf '%s%s' "$root" "$1"; }
log() { printf 'astra-installed-boot: %s\n' "$*" >&2; }

asset="$(at /usr/share/astra-retro-os/grub-background.png)"
grubdir="$(at /boot/grub2)"
grubcfg="$grubdir/grub.cfg"
entries="$(at /boot/loader/entries)"
[[ -s "$asset" ]] || { log 'GRUB artwork not found; skipping'; exit 0; }
[[ -s "$grubcfg" ]] || { log 'No installed GRUB config; skipping (another bootloader?)'; exit 0; }

# Fedora/bootupd uses user.cfg before blscfg; older GRUB generated configs
# include custom.cfg. Modify only the supported extension point.
config=''
if grep -Eq '^[[:space:]]*source[[:space:]].*user\.cfg' "$grubcfg"; then
  config="$grubdir/user.cfg"
elif grep -Eq '^[[:space:]]*source[[:space:]].*custom\.cfg' "$grubcfg"; then
  config="$grubdir/custom.cfg"
else
  log 'No user.cfg/custom.cfg source in grub.cfg; leaving GRUB unchanged'
  exit 0
fi

install -d "$grubdir" "$entries"
if ! cmp -s "$asset" "$grubdir/astra-background.png"; then
  install -m 0644 "$asset" "$grubdir/astra-background.png"
fi

# The signed EFI stub may start with $prefix=/EFI/fedora, which does not
# contain gfxterm_background.mod. GRUB loads its external modules from the
# boot partition once the prefix is redirected temporarily.
for arch in x86_64-efi arm64-efi; do
  modules="$(at "/usr/lib/grub/$arch")"
  [[ -d "$modules" ]] || continue
  install -d "$grubdir/$arch"
  cp -au "$modules/." "$grubdir/$arch/"
done
fontdir="$grubdir/fonts"
for candidate in "$(at /usr/share/grub/unicode.pf2)" "$(at /usr/share/grub2/unicode.pf2)"; do
  if [[ -s "$candidate" ]]; then
    install -d "$fontdir"
    if ! cmp -s "$candidate" "$fontdir/unicode.pf2"; then
      install -m 0644 "$candidate" "$fontdir/unicode.pf2"
    fi
    break
  fi
done

# Only replace our managed section, keeping user-managed GRUB settings.
start='# BEGIN ASTRA RETRO OS INSTALLED BRANDING'
end='# END ASTRA RETRO OS INSTALLED BRANDING'
tmp="$(mktemp "$grubdir/.astra-grub.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
if [[ -f "$config" ]]; then
  awk -v start="$start" -v end="$end" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$config" > "$tmp"
fi
cat >> "$tmp" <<'GRUB'
# BEGIN ASTRA RETRO OS INSTALLED BRANDING
# GRUB root may refer to /boot or to the root filesystem.
set astra_boot_prefix=
if search --no-floppy --file --set=astra_boot /grub2/astra-background.png; then
    set astra_boot_prefix="($astra_boot)/grub2"
elif search --no-floppy --file --set=astra_boot /boot/grub2/astra-background.png; then
    set astra_boot_prefix="($astra_boot)/boot/grub2"
fi
if [ -n "$astra_boot_prefix" ]; then
    set astra_previous_prefix=$prefix
    set prefix=$astra_boot_prefix
    insmod all_video
    insmod gfxterm
    insmod gfxterm_background
    insmod png
    if [ -f "$astra_boot_prefix/fonts/unicode.pf2" ]; then
        loadfont "$astra_boot_prefix/fonts/unicode.pf2"
    fi
    set gfxmode=1920x1080,1600x900,1366x768,1280x720,auto
    terminal_output gfxterm
    set gfxpayload=keep
    set menu_color_normal=white/black
    set menu_color_highlight=black/light-cyan
    background_image -m stretch "$astra_boot_prefix/astra-background.png"
    set prefix=$astra_previous_prefix
fi
# Do not override saved_entry/next_entry: bootc manages deployment selection.
# The normal OSTree/BLS entry remains the default, the debug entry sorts last.
# Escape or Shift opens the menu within this window.
if [ "${menu_show_once}" = 1 ] || [ "${boot_success}" = 0 ]; then
    set timeout_style=menu
else
    set timeout_style=hidden
fi
set timeout=5
# END ASTRA RETRO OS INSTALLED BRANDING
GRUB
if ! cmp -s "$tmp" "$config"; then
  chmod 0644 "$tmp"
  mv -f "$tmp" "$config"
fi

# Copy the newest normal BLS entry (which can refer to a staged deployment).
# GRUB sorts BLS filenames in reverse lexical/version order; 0000-... sorts
# below Fedora's ostree-/bootc_ and hexadecimal machine-id names.
debug="$entries/0000-astra-retro-debug-0.conf"
source_bls=''
if [[ -d "$entries" ]]; then
  while IFS= read -r candidate; do
    [[ "$candidate" != "$debug" ]] || continue
    if grep -Eq '^linux[[:space:]]+' "$candidate" && grep -Eq '^options[[:space:]]+' "$candidate"; then
      source_bls="$candidate"
      break
    fi
  done < <(find "$entries" -maxdepth 1 -type f -name '*.conf' -print | LC_ALL=C sort -r)
fi
[[ -n "$source_bls" ]] || { log 'No normal BLS entry yet; debug entry deferred'; exit 0; }

tmp_bls="$(mktemp "$entries/.astra-debug.XXXXXX")"
trap 'rm -f "$tmp" "$tmp_bls"' EXIT
awk '
  BEGIN {has_title=0; has_sort=0; has_options=0}
  /^title[[:space:]]/ {
    print "title Astra Retro OS (Debug)"; has_title=1; next
  }
  /^sort-key[[:space:]]/ {
    print "sort-key zz-astra-retro-debug"; has_sort=1; next
  }
  /^options[[:space:]]/ {
    out="options"
    for (i=2; i<=NF; i++) {
      if ($i != "quiet" && $i != "rhgb" && $i != "splash") out=out " " $i
    }
    print out " plymouth.enable=0 rd.plymouth=0 loglevel=7 ignore_loglevel systemd.show_status=1 rd.systemd.show_status=1 systemd.log_level=debug rd.systemd.log_level=debug"
    has_options=1; next
  }
  /^grub_hotkey[[:space:]]/ {next}
  {print}
  END {
    if (!has_title) print "title Astra Retro OS (Debug)"
    if (!has_sort) print "sort-key zz-astra-retro-debug"
    if (!has_options) exit 2
  }
' "$source_bls" > "$tmp_bls"
if ! cmp -s "$tmp_bls" "$debug"; then
  chmod 0644 "$tmp_bls"
  mv -f "$tmp_bls" "$debug"
fi
log 'Installed GRUB artwork, hidden menu and BLS debug entry synchronised'
