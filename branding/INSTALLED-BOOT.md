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
