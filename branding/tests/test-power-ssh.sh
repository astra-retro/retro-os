#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash -n branding/install-common.sh
python3 - <<'PY'
import configparser
from pathlib import Path

p = Path("branding/desktop/27-astra-always-on")
d = configparser.ConfigParser(interpolation=None)
assert d.read(p, encoding="utf-8") == [str(p)]
assert d["org/gnome/desktop/session"]["idle-delay"] == "uint32 0"
power = d["org/gnome/settings-daemon/plugins/power"]
for key in ["sleep-inactive-ac-type", "sleep-inactive-battery-type"]:
    assert power[key] == "'nothing'", (key, power[key])
for key in ["sleep-inactive-ac-timeout", "sleep-inactive-battery-timeout"]:
    assert power[key] == "0", (key, power[key])
assert d["org/gnome/desktop/screensaver"]["idle-activation-enabled"] == "false"
assert "lock-enabled" not in d["org/gnome/desktop/screensaver"]

conf = configparser.ConfigParser(interpolation=None)
p = Path("branding/systemd/60-astra-no-suspend.conf")
assert conf.read(p, encoding="utf-8") == [str(p)]
login = conf["Login"]
for key in ["IdleAction", "HandleLidSwitch", "HandleLidSwitchExternalPower", "HandleLidSwitchDocked"]:
    assert login[key] == "ignore", (key, login[key])

common = Path("branding/install-common.sh").read_text()
installed = common.index('if [[ "$mode" == installed ]]; then')
for phrase in [
    '/etc/dconf/db/local.d/27-astra-always-on',
    '/etc/dconf/db/gdm.d/27-astra-always-on',
    '/usr/lib/systemd/logind.conf.d/60-astra-no-suspend.conf',
    'systemctl mask sleep.target suspend.target hibernate.target',
    'hybrid-sleep.target suspend-then-hibernate.target',
    'systemctl enable sshd.service',
    'firewall-offline-cmd --add-service=ssh',
]:
    assert phrase in common and common.index(phrase) > installed, phrase
assert common.index('27-astra-always-on') < common.index('dconf update')
container = Path("Containerfile").read_text()
assert "openssh-server" in container and "firewalld" in container
live = Path("branding/install-live.sh").read_text()
assert "sshd.service" not in live
assert "27-astra-always-on" not in live
PY
echo 'Installed always-on power and SSH checks passed'
