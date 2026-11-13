#!/usr/bin/env bash
# Validate the exact GRUB code emitted by sync-installed-boot.sh.
# This must run with a *real* GRUB parser, not the unit-test shim.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$script_dir/sync-installed-boot.sh"
if command -v grub2-script-check >/dev/null 2>&1; then
  checker=grub2-script-check
elif command -v grub-script-check >/dev/null 2>&1; then
  checker=grub-script-check
else
  echo 'ERROR: grub2-script-check/grub-script-check is not installed' >&2
  exit 1
fi
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
awk '
  /^cat >> "\$tmp" <<\x27GRUB\x27$/ {in_grub=1; next}
  in_grub && /^GRUB$/ {in_grub=0; done=1; exit}
  in_grub {print}
  END {if (!done) exit 1}
' "$script" > "$tmp"
[[ -s "$tmp" ]]
"$checker" "$tmp"
echo "Installed GRUB generated fragment passed $checker"
