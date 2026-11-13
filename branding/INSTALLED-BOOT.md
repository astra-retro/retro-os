# Astra Retro OS — installed boot parity

The OCI image already uses `branding/install-common.sh` for **both** Live
and installed payloads. Wallpaper, GNOME logo, os-release and Plymouth are
shared. The installed initramfs is generated in generic mode and must bundle
the Astra script theme explicitly. The normal boot also needs `quiet rhgb`
to show the Plymouth splash instead of routine kernel/service logs.
The GRUB disk contents are synchronized separately.

## Installed GRUB

- `astra-installed-boot.service` copies the existing GRUB image and EFI
  modules to `/boot/grub2`, then writes a managed fragment into
  `/boot/grub2/user.cfg` (bootupd static GRUB) or `custom.cfg`
  (legacy Fedora GRUB). Existing custom lines are kept.
- The installed graphical splash uses the same five-second
  `sleep --interruptible` mechanism as the Live ISO, keeping the GRUB
  background visible. Press **Escape** during the delay to display the menu
  indefinitely; otherwise it boots the normal BLS default without displaying
  a menu. Recovery/one-shot requests show a regular ten-second menu.
  When `sleep` or the background is unavailable the script falls back to a
  visible timed menu, so boot selection remains possible.
- Normal BLS/OSTree boot entries are kept unchanged, including their default
  selection and rollback semantics. A low-sorting generated BLS entry
  `0000-astra-retro-debug-0.conf` starts the active/staged deployment with
  Plymouth disabled and verbose logging.
- `astra-installed-boot.path` resynchronises the debug entry after changes to
  BLS files. The oneshot service also runs after boot.
- The Live installer invokes the same command best-effort during its post
  phase, so the first installed boot can be themed when /boot is available.

No `grub2-install`, `grub2-mkconfig`, edits to the UEFI shim/GRUB stub
or changes to `saved_entry` are performed.

### Local validation

```bash
bash branding/tests/test-installed-boot.sh
sudo systemctl status astra-installed-boot.service astra-installed-boot.path
sudo cat /boot/grub2/user.cfg
sudo cat /boot/loader/entries/0000-astra-retro-debug-0.conf
```

The test covers first installation, idempotency, GRUB user customisations,
updated BLS entries, and an unknown GRUB layout. A real UEFI/Secure Boot
boot should still be validated in a VM before merging.

## Installed Plymouth and kernel arguments

- `branding/kargs/10-astra-graphical-boot.toml` adds `quiet rhgb` via
  `/usr/lib/bootc/kargs.d/`, which bootc applies on installation and image
  upgrades. It avoids unmanaged changes to GRUB or BLS files.
- `branding/dracut/51astra-plymouth/module-setup.sh` explicitly embeds the
  scripted splash, artwork, default theme symlink, and renderer plugin in the
  generic Dracut initramfs while retaining `--no-hostonly` for portability.
- `build_files/build-initramfs.sh` validates the themed initramfs during the
  OCI build; missing assets or script.so now fail the build instead of
  silently showing console logs.
- The generated BLS Debug entry intentionally removes `quiet rhgb` and
  disables Plymouth so that diagnostics remain visible.

To check a booted installed machine:

```bash
cat /proc/cmdline
plymouth-set-default-theme
sudo lsinitrd /usr/lib/modules/$(uname -r)/initramfs.img | grep -E 'astra-retro-os|plymouth/script.so'
sudo journalctl -b -u plymouth-start.service -u plymouth-quit.service --no-pager
sudo grubby --info=ALL | grep -E '^(index|title|args)='
```

If `/proc/cmdline` lacks `quiet rhgb`, check the booted OSTree deployment
(`bootc status`). A new OCI build/deployment is required: merely
rebuilding the Live ISO does not replace the already installed OS image.

If `plymouth.enable=0` is present, a Debug entry was selected; choose the
normal boot entry and try again. Serial consoles and firmware framebuffer
behavior can also prevent the graphical splash on some machines.

## Shared GNOME dock (Live and installed)

- The same Fedora `gnome-shell-extension-dash-to-dock` RPM is installed
  into the Live image and the installed OCI image.
- `branding/desktop/25-astra-dock` is applied by `install-common.sh`
  to both images. It enables Dash to Dock and the Fedora background-logo
  extension; the dock is bottom-aligned, fixed, and neither automatically
  nor intelligently hidden.
- The Live-only `30-astra-live` dconf file contains only installer favorites,
  not the shared dock settings. The installed GNOME desktop does **not**
  receive the Anaconda installer launcher.
- `dconf update` compiles these machine defaults. They do **not** lock keys
  and so do not overwrite settings saved in an existing user's dconf database.

To inspect the *logged-in desktop user* on an installed system:

```bash
gnome-extensions list | grep dash-to-dock
gnome-extensions list --enabled | grep dash-to-dock
gsettings get org.gnome.shell.extensions.dash-to-dock dock-fixed
gsettings get org.gnome.shell.extensions.dash-to-dock autohide
gsettings get org.gnome.shell.extensions.dash-to-dock intellihide
```

If the user previously stored different settings, after installing the updated
OCI image run these commands **as the desktop user, not root**, then sign out
and back in:

```bash
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
gsettings set org.gnome.shell.extensions.dash-to-dock autohide false
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false
```

## GDM login keyboard (French AZERTY)

The Live ISO is explicitly configured for the French keyboard, but that
Live-only configuration is not installed into the persistent bootc image.
The logged-in GNOME user's AZERTY selection therefore does not guarantee
an AZERTY layout at the GDM password prompt.

The installed image now supplies an **unlocked** GDM dconf default at
`/etc/dconf/db/gdm.d/30-astra-gdm-keyboard` with `fr` first and `us`
available as a secondary layout. The system/user settings are not locked:
a different deployment locale or keyboard choice can override the default.
`branding/install-common.sh` runs `dconf update` at image build time.

After deploying the corrected image and rebooting, verify the GDM dconf
default with:

```bash
cat /etc/dconf/db/gdm.d/30-astra-gdm-keyboard
DCONF_PROFILE=gdm gsettings get org.gnome.desktop.input-sources sources
localectl status
```

The `gsettings` command invoked as root may show root's session/user
settings rather than the live GDM session: validate the actual keyboard
layout on the password prompt after reboot. GDM may also use system
`localed` or per-user AccountsService input sources on some releases; a
runtime UEFI login test is still necessary.

## First-boot language / timezone / user creation (GNOME Initial Setup)

Before a user account exists, GNOME Initial Setup runs inside a **special GDM
session**, not the ordinary desktop session. The latter uses the `local`
dconf database, whereas the GDM session reads the `gdm` profile/database.

The installed OCI image now ships
`branding/desktop/20-astra-gdm-background` to
`/etc/dconf/db/gdm.d/20-astra-gdm-background`, setting the light/dark
background URI to the **same Astra wallpaper** as the normal desktop.
The `org.gnome.login-screen.logo` setting is explicitly cleared (`logo=''`)
because it places a logo *in front of the greeter*, not behind it: previously,
the full-size 512px Astra icon could obstruct the password prompt.
`install-common.sh` ensures the `gdm` database is in GDM's dconf profile,
preserving any existing vendor/admin profile, and runs `dconf update`.

This does not remove or bypass GNOME Initial Setup and is applied to the
installed image only. Its dconf settings do not lock user preferences.

**Important:** GNOME Shell's GDM/Initial Setup interface may render a
built-in or blurred background despite a configured wallpaper. The patch
configures supported GSettings values, but the exact first-boot visual
appearance on Fedora 45 requires a real fresh-install VM test. Do not claim
full visual parity until verified.

Checks on the installed image:

```bash
cat /etc/dconf/profile/gdm
cat /etc/dconf/db/gdm.d/20-astra-gdm-background
ls -l /etc/dconf/db/gdm /usr/share/backgrounds/astra-retro-os/wallpaper.png
```

A normal login after the first boot does not retest GNOME Initial Setup.
Use a **fresh installation with no user** to validate the original symptom.

## Settings — remove GNOME donation row (installed only)

GNOME's **Settings > System > About** contains a compiled `Support GNOME` / `Donate` group, not a dconf option. The installed image overlays only the `cc-about-page.ui` resource via GLib's `G_RESOURCE_OVERLAYS`; the GNOME Settings binary and other pages are unchanged. The overlay is compiled from GNOME's GPL-2.0-or-later original Blueprint template for GNOME 49/50 or 51, with only that group removed, using `blueprint-compiler` during image build. An unrecognized GNOME major version fails the image build until templates can be reviewed. The resource overlay is supplied via `/usr/lib/environment.d/70-astra-settings-ui.conf`; log out and back in to load it in the user session. Only installed OS is changed; Live is unchanged. Recheck after upstream GNOME upgrades.

## Disable the optional GNOME Welcome Tour on first desktop login

The installed image ships `branding/desktop/26-astra-no-welcome-tour`
as an **unlocked** dconf default in the `local` database:
`org.gnome.shell welcome-dialog-last-shown-version='4294967295'`.
GNOME Shell treats a very high last-shown version as a request not to
display the optional welcome dialog. It is applied only to the installed
OCI image, and `install-common.sh` verifies that the running GNOME Shell
schema provides this key, failing the image build if compatibility changes.

This intentionally **does not** disable `gnome-initial-setup`, change
`InitialSetupEnable`, remove any GDM services, or skip language, timezone
and initial-user creation. It leaves GNOME Tour available for manual use
and lets users override the default. Because an existing user's personal
dconf database has precedence, it may still be necessary to reset the
personal key for a machine previously configured.

To verify as a freshly created desktop user:

```bash
gsettings get org.gnome.shell welcome-dialog-last-shown-version
```

Expected: `'4294967295'`. For existing user data with a lower stored
value, `gsettings reset org.gnome.shell welcome-dialog-last-shown-version`
restores the new system default; sign out/in afterward.

### GDM login screen: obstructing logo regression (fixed)

`org.gnome.login-screen.logo` is a **foreground logo**, unrelated to the
wallpaper. Do not set it to `/usr/share/icons/hicolor/512x512/apps/astra-retro-os.png`.
The installed GDM profile now writes `logo=''` so an update removes the
previous oversized logo even on an existing installation. The logo remains
available in GNOME Settings, the wallpaper overlay and Plymouth.

The `org.gnome.desktop.background` settings in the GDM dconf database
are best-effort GNOME Initial Setup defaults; GNOME Shell's actual greeter
background may remain a theme-defined backdrop and requires a separate,
version-compatible solution. Removing the obstructing foreground image
restores the login UI independently of whether wallpaper theming is available.

After updating the installed image, reboot rather than restarting GDM in
an active session. To verify from a system with the fixed deployment:

```bash
DCONF_PROFILE=gdm gsettings get org.gnome.login-screen logo
```

Expected: `''`. If the greeter session already cached its prior dconf
value, a full reboot ensures it is recreated.

## Installed-only always-on display, no suspend and SSH

Astra Retro OS installed images deliberately keep the screen active and
prevent sleep. The Live ISO is unchanged.

- `branding/desktop/27-astra-always-on` is installed into both the GNOME
  user dconf database (`local`) and GDM's separate database (`gdm`).
  GNOME's idle-delay is zero, automatic AC/battery sleep is disabled, and
  idle screensaver activation is disabled. The user's manual lock remains
  available. These settings are **defaults**, not forced locks; existing
  users may have personal settings that take priority.
- `branding/systemd/60-astra-no-suspend.conf` sets `IdleAction=ignore`
  and disables lid-triggered sleep. The systemd sleep/suspend/hibernate
  targets are masked in the installed image (including manual suspension).
  This increases energy use, especially on laptops.
- `openssh-server` and `firewalld` are installed in the OCI image,
  `sshd.service` is enabled at boot, and the default firewalld zone
  permits the SSH service (TCP port 22). No SSH password, account, or
  authorized key is generated. **SSH access is exposed to networks allowed
  by the firewall and requires valid authentication.** Hardening
  (key-only authentication, remote network restriction) remains an
  administrator responsibility.

Validation after updating and rebooting:

```bash
gsettings get org.gnome.desktop.session idle-delay
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type
systemd-analyze cat-config systemd/logind.conf
systemctl is-enabled sleep.target suspend.target hibernate.target
systemctl is-enabled sshd.service
systemctl is-active sshd.service
sudo firewall-cmd --list-services
ss -lnt | grep ':22 '
```

Expected: idle delay `uint32 0`, AC/battery sleep types `'nothing'`,
suspend-related units `masked`, and `sshd.service` `enabled` and
`active`. The firewall's active zone must allow SSH. Existing GNOME
users may need to reset their personal power/idle settings for new
system defaults to apply.

**Security:** an enabled SSH server listens for authenticated connections.
If the machine is exposed to untrusted networks, configure key-only
authentication and restrict access using firewalld.

## GDM login greeter wallpaper (pixel art)

The existing `branding/assets/wallpaper-pixel-art.png` is now required and
copied into the installed OCI at
`/usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png` (0644).
The normal desktop continues using its separate `wallpaper.png`.

GNOME 49 draws the pre-login greeter from its compiled Shell theme resource.
The installed build runs `branding/gdm/install-greeter-wallpaper.py`: it
extracts **all original resource members**, appends a background image only
to the `#lockDialogGroup` selector in dark/light/high-contrast CSS, rebuilds
the resource, and checks its complete member set. An incompatible upstream
resource makes the build fail instead of damaging login controls. The GDM
dconf profile also refers to the pixel-art asset, with `logo=''` so the
login dialog is never hidden by an oversized foreground logo.

The change is applied inside the OCI build to immutable `/usr`, not by
writing to `/usr` after installation. This unsupported GNOME theme
customization needs a visual UEFI/GDM test before merging.

After updating, check:
```bash
stat /usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png
gresource extract /usr/share/gnome-shell/gnome-shell-theme.gresource \
  /org/gnome/shell/theme/gnome-shell-dark.css | grep -A8 'Astra Retro OS GDM'
```

## GNOME user avatar: circular Astra logo for newly created accounts

GNOME 49/50 uses a **circular clipping mask** for account avatars; changing
only the Shell CSS border radius does not reliably change the image mask.
The original Astra icon is a square with rounded corners and would be cropped.
The installed image now derives a 512x512 PNG from the **existing SVG** logo:
its artwork is scaled to 72% and centered on a dark circular background,
leaving all details visible inside the GNOME circular crop. The generated
asset lives at `/usr/share/pixmaps/faces/astra-retro-os.png`.

AccountsService standard and administrator user templates are configured to
point to this image while keeping all other vendor profile settings. GNOME
Initial Setup sometimes overrides template defaults by generating its own
initials avatar. A lightweight one-shot timer (every 60 seconds after boot)
replaces **only** images tagged `tEXt::source=gnome-generated` by GNOME,
using the AccountsService `SetIconFile` API. It explicitly skips
non-generated icons, non-default icon paths, and system accounts, so avatars
selected manually in GNOME Settings or the Initial Setup chooser remain
unchanged. Existing autogenerated initials icons may also be updated once.
The change only affects the installed OCI, not the Live environment.

After updating and rebooting, check:

```bash
file /usr/share/pixmaps/faces/astra-retro-os.png
systemctl status astra-default-avatar.timer
sudo journalctl -u astra-default-avatar.service -b --no-pager
sudo grep '^Icon=' /var/lib/AccountsService/users/USERNAME
```

A first-boot GNOME user-creation VM test is required before merging.
