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
[[ -s "$asset" ]] || { log 'ERROR: installed GRUB artwork missing from OCI image'; exit 1; }
[[ -s "$grubcfg" ]] || { log 'ERROR: /boot/grub2/grub.cfg is missing or empty'; exit 1; }

# Modern bootupd static GRUB sources console.cfg BEFORE blscfg, and custom.cfg
# AFTER blscfg. Initialise the graphics in the early console.cfg hook, while
# preserving legacy user.cfg/custom.cfg fallback layouts. Doing this after
# blscfg is less reliable on signed EFI GRUB builds.
# Recognise inline source directives and ignore commented-out ones.
# Never rewrite bootupd's grub.cfg or its signed EFI stub.
grub_sources="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$grubcfg")"
config=''
if grep -Eq '(^|[[:space:];])source[[:space:]]+[^[:space:];#]*console\.cfg' <<< "$grub_sources"; then
  config="$grubdir/console.cfg"
elif grep -Eq '(^|[[:space:];])source[[:space:]]+[^[:space:];#]*user\.cfg' <<< "$grub_sources"; then
  config="$grubdir/user.cfg"
elif grep -Eq '(^|[[:space:];])source[[:space:]]+[^[:space:];#]*custom\.cfg' <<< "$grub_sources"; then
  config="$grubdir/custom.cfg"
else
  log 'ERROR: no sourced console.cfg/user.cfg/custom.cfg in /boot/grub2/grub.cfg; cannot safely install branding'
  exit 1
fi
log "Selected GRUB hook: ${config#"$root"}"

# Fedora Atomic/bootc deliberately mounts /boot read-only after boot. The
# systemd service runs in its own mount namespace; temporarily remount /boot
# writable only for this synchronisation, then restore read-only on *every*
# exit path. In Anaconda's %post (ASTRA_ROOT) restore the installer mount too.
# Refuse to remount '/' or another parent filesystem when /boot is not an
# independent mountpoint: that could change the host OS unexpectedly.
boot_mount="$(at /boot)"
boot_remounted=0
tmp=''
tmp_bls=''
cleanup() {
  local status=$?
  trap - EXIT
  [[ -z "$tmp" ]] || rm -f "$tmp" || true
  [[ -z "$tmp_bls" ]] || rm -f "$tmp_bls" || true
  if [[ "$boot_remounted" == 1 ]]; then
    if ! mount --options-source=disable -o remount,ro "$boot_mount"; then
      log "ERROR: unable to restore read-only $boot_mount"
      status=1
    else
      log "Restored read-only $boot_mount"
    fi
  fi
  exit "$status"
}
trap cleanup EXIT

boot_vfs_options="$(findmnt -n -o VFS-OPTIONS -T "$grubdir")" || {
  log "ERROR: unable to inspect $grubdir mount options"
  exit 1
}
case ",$boot_vfs_options," in
  *,ro,*)
    if ! mountpoint -q "$boot_mount"; then
      log "ERROR: $boot_mount is not a separate mountpoint; refusing to remount its parent"
      exit 1
    fi
    log "Temporarily remounting read-only $boot_mount writable"
    mount --options-source=disable -o remount,rw "$boot_mount" || {
      log "ERROR: failed to remount $boot_mount writable"
      exit 1
    }
    boot_remounted=1
    boot_vfs_options="$(findmnt -n -o VFS-OPTIONS -T "$grubdir")" || exit 1
    case ",$boot_vfs_options," in
      *,ro,*)
        log "ERROR: $boot_mount is still read-only after remount"
        exit 1
        ;;
    esac
    ;;
esac

# mkdir -p leaves existing directory permissions unchanged. 'install -d'
# tries to chmod existing directories, which failed immediately on read-only
# Fedora Atomic /boot mounts even when the directory already existed.
mkdir -p "$grubdir" "$entries"
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

# On upgrade a previous image may have written the branding into custom.cfg.
# If we now use console.cfg, the old block MUST be removed or it will be run
# a second time after blscfg, undoing the early graphical setup. Never delete
# user-authored lines, and fail on damaged markers rather than corrupting them.
for candidate in "$grubdir/console.cfg" "$grubdir/user.cfg" "$grubdir/custom.cfg"; do
  [[ -f "$candidate" ]] || continue
  begin_count="$(grep -Fxc "$start" "$candidate" || true)"
  end_count="$(grep -Fxc "$end" "$candidate" || true)"
  if [[ "$begin_count" != "$end_count" || "$begin_count" -gt 1 ]]; then
    log "ERROR: incomplete or repeated Astra markers in $candidate"
    exit 1
  fi
done
tmp="$(mktemp "$grubdir/.astra-grub.XXXXXX")"
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
set astra_background_ok=0
set astra_sleep_available=0
set astra_boot_prefix=
if search --no-floppy --file --set=astra_boot /grub2/astra-background.png; then
    set astra_boot_prefix="($astra_boot)/grub2"
elif search --no-floppy --file --set=astra_boot /boot/grub2/astra-background.png; then
    set astra_boot_prefix="($astra_boot)/boot/grub2"
fi
if [ -n "$astra_boot_prefix" ]; then
    set astra_previous_prefix=$prefix
    set prefix=$astra_boot_prefix
    # shim_lock forbids loading unsigned modules from the /boot filesystem.
    # Fedora's signed GRUB may already contain the display commands: use
    # those built-ins directly in Secure Boot mode, never external insmod.
    set astra_secure_boot=0
    if [ "${shim_lock}" = y ]; then
        set astra_secure_boot=1
    fi
    if [ "${lockdown}" = y ]; then
        set astra_secure_boot=1
    fi
    if [ "${astra_secure_boot}" = 0 ]; then
        insmod all_video
        insmod gfxterm
        insmod gfxterm_background
        insmod png
    fi
    # gfxterm without an available font displays '?' instead of the menu
    # frame glyphs. Never switch to gfxterm unless a Unicode font loads.
    set astra_font_ok=0
    if loadfont unicode; then
        set astra_font_ok=1
    elif [ -f "$astra_boot_prefix/fonts/unicode.pf2" ]; then
        if loadfont "$astra_boot_prefix/fonts/unicode.pf2"; then
            set astra_font_ok=1
        fi
    fi
    if [ "${astra_font_ok}" = 1 ]; then
        set gfxmode=1920x1080,1600x900,1366x768,1280x720,auto
        if terminal_output gfxterm; then
            set gfxpayload=keep
            set menu_color_normal=white/black
            set menu_color_highlight=black/light-cyan
            if background_image -m stretch "$astra_boot_prefix/astra-background.png"; then
                set astra_background_ok=1
            fi
        fi
    fi
    # The original EFI prefix may be /EFI/fedora (without sleep.mod).
    # The sleep module is attempted only when shim_lock is off; it is not
    # necessarily embedded in the signed Fedora GRUB image.
    if [ "${astra_secure_boot}" = 0 ]; then
        if insmod sleep; then
            set astra_sleep_available=1
        fi
    fi
    set prefix=$astra_previous_prefix
fi
# Do not override saved_entry/next_entry: bootc manages deployment selection.
# The normal OSTree/BLS entry remains the default, the debug entry sorts last.
#
# On the Live ISO we use interruptible sleep to keep the splash visible while
# waiting for Escape, then expose the menu indefinitely. Use the SAME working
# behavior here instead of timeout_style=hidden: the latter may auto-boot
# without exposing the menu in the firmware/GRUB combination used by installed
# systems. The sleep happens while the GRUB config is being read; the final
# menu timeout takes effect once blscfg has populated the BLS entries.
set timeout_style=menu
# GRUB's script lexer cannot parse the shell-style '||' expression that
# previously appeared here and failed grub2-script-check at console.cfg:46.
# Compute the OR using simple GRUB commands instead.
set astra_force_menu=0
if [ "${menu_show_once}" = 1 ]; then
    set astra_force_menu=1
fi
if [ "${boot_success}" = 0 ]; then
    set astra_force_menu=1
fi
if [ "${astra_force_menu}" = 1 ]; then
    # Recovery and explicit one-shot menu requests should not be hidden.
    set timeout=10
elif [ "${astra_background_ok}" = 1 ]; then
    if [ "${astra_sleep_available}" = 1 ]; then
        if sleep --interruptible 5; then
            # 5 seconds with no key: boot the normal default immediately.
            set timeout=0
        else
            # Escape (or supported interrupt keys): show menu indefinitely.
            set timeout=-1
        fi
    else
        # Fail open: if this GRUB build lacks sleep, keep the menu accessible.
        set timeout=5
    fi
else
    # If graphics cannot be loaded, keep a visible normal boot menu.
    set timeout=5
fi
# END ASTRA RETRO OS INSTALLED BRANDING
GRUB
# Check the *generated* fragment with GRUB's own parser before replacing any
# boot configuration. Fedora uses grub2-script-check; Debian uses grub-script-check.
# If the checker is unavailable, fail closed instead of shipping unparsed GRUB.
grub_checker=''
if command -v grub2-script-check >/dev/null 2>&1; then
  grub_checker=grub2-script-check
elif command -v grub-script-check >/dev/null 2>&1; then
  grub_checker=grub-script-check
fi
if [[ -z "$grub_checker" ]]; then
  log 'ERROR: no GRUB script checker available; refusing to install unvalidated configuration'
  exit 1
fi
if ! "$grub_checker" "$tmp"; then
  log 'ERROR: generated GRUB syntax invalid; existing configuration preserved'
  exit 1
fi
if ! cmp -s "$tmp" "$config"; then
  chmod 0644 "$tmp"
  mv -f "$tmp" "$config"
fi

# Migrate previous managed sections out of other hooks. Keep every non-Astra
# directive, including user customizations, unchanged.
for oldconfig in "$grubdir/console.cfg" "$grubdir/user.cfg" "$grubdir/custom.cfg"; do
  [[ "$oldconfig" != "$config" && -f "$oldconfig" ]] || continue
  grep -Fxq "$start" "$oldconfig" || continue
  oldtmp="$(mktemp "$grubdir/.astra-legacy.XXXXXX")"
  awk -v start="$start" -v end="$end" '
    $0 == start {skip=1; next}
    $0 == end {skip=0; next}
    !skip {print}
  ' "$oldconfig" > "$oldtmp"
  chmod --reference="$oldconfig" "$oldtmp"
  if ! cmp -s "$oldtmp" "$oldconfig"; then
    mv -f "$oldtmp" "$oldconfig"
  else
    rm -f "$oldtmp"
  fi
done

# Copy the newest normal BLS entry (which can refer to a staged deployment).
# The debug BLS entry MUST sort after every normal entry. Filename 0000-...
# sorts last on Fedora's filename-based blscfg; new GRUB also sorts by the
# optional "sort-key". NEVER give Debug a sort-key: an entry with sort-key
# sorts ahead of an entry without it (and zz- was the cause of Debug booting
# first). Use version 0 to place it behind normal versions with the same
# machine-id even on versions of GRUB that sort by the BLS metadata.
# Do not touch saved_entry/next_entry: bootc owns the default deployment.
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
awk '
  BEGIN {has_title=0; has_version=0; has_options=0}
  /^title[[:space:]]/ {
    print "title Astra Retro OS (Debug)"; has_title=1; next
  }
  # Never copy the source deployment sort-key: it makes Debug first when
  # normal bootc BLS snippets do not define one.
  /^sort-key[[:space:]]/ {next}
  /^version[[:space:]]/ {print "version 0"; has_version=1; next}
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
    if (!has_version) print "version 0"
    if (!has_options) exit 2
  }
' "$source_bls" > "$tmp_bls"
if ! cmp -s "$tmp_bls" "$debug"; then
  chmod 0644 "$tmp_bls"
  mv -f "$tmp_bls" "$debug"
fi
log "Installed GRUB artwork and BLS debug entry synchronised via ${config#"$root"}"
