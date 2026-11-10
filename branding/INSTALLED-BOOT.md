# Astra Retro OS — installed boot parity

The OCI image already uses `branding/install-common.sh` for **both** Live
and installed payloads. Wallpaper, GNOME logo, os-release and Plymouth are
shared; `build_files/build-initramfs.sh` includes Plymouth in the installed
initramfs. Only the GRUB disk contents need syncing after installation.

## Installed GRUB

- `astra-installed-boot.service` copies the existing GRUB image and EFI
  modules to `/boot/grub2`, then writes a managed fragment into
  `/boot/grub2/user.cfg` (bootupd static GRUB) or `custom.cfg`
  (legacy Fedora GRUB). Existing custom lines are kept.
- The normal menu is hidden for five seconds and can be revealed with
  **Escape** or **Shift**. Recovery/one-shot GRUB flags can show it.
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
