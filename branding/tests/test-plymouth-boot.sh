#!/usr/bin/env bash
# Static checks run on CI's Ubuntu runner; the Fedora OCI build separately
# validates real Dracut/Plymouth packaging using lsinitrd.
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/dracut/51astra-plymouth/module-setup.sh
bash -n branding/install-common.sh
bash -n build_files/build-initramfs.sh
python3 - <<'PY'
import pathlib
import tomllib
path = pathlib.Path('branding/kargs/10-astra-graphical-boot.toml')
args = tomllib.loads(path.read_text())['kargs']
assert args == ['quiet', 'rhgb'], args
PY
grep -Fq -- '--add astra-plymouth' build_files/build-initramfs.sh
grep -Fq -- '--no-hostonly' build_files/build-initramfs.sh
grep -Fq '51astra-plymouth/module-setup.sh' branding/install-common.sh
grep -Fq '10-astra-graphical-boot.toml' branding/install-common.sh
grep -Fq 'plymouth-splash.png' branding/dracut/51astra-plymouth/module-setup.sh
grep -Fq 'script.so' branding/dracut/51astra-plymouth/module-setup.sh
echo 'Installed Plymouth branding static checks passed'
