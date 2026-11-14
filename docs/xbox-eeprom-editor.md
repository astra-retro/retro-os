# Xbox EEPROM Editor, Mono and xorriso

Astra Retro OS installs these tools into the **OCI image at build time**:

| Component | Source | Purpose |
| --- | --- | --- |
| xorriso | Fedora RPM | Create, inspect and manipulate ISO images |
| mono-core, mono-winforms | Fedora RPM | .NET/Windows Forms runtime |
| XboxEepromEditor | [Ernegien/XboxEepromEditor](https://github.com/Ernegien/XboxEepromEditor) release 1.0.0.1 | Graphical original Xbox EEPROM editor |

XboxEepromEditor is a Windows Forms executable, not a native Linux binary.
It is stored in `/usr/libexec/retro-os/XboxEepromEditor/` and started with
`mono` using `/usr/bin/xbox-eeprom-editor`, also available via the GNOME
application menu as **Xbox EEPROM Editor**.

The launcher sets the working directory to
`${XDG_STATE_HOME:-$HOME/.local/state}/xbox-eeprom-editor`, because upstream
writes `XboxEepromEditor.log` relative to the current working directory.
This keeps user-generated logs outside immutable `/usr`.

The installer pins the upstream **1.0.0.1** release asset URL, validates the
128970-byte file length and ZIP CRC, verifies the expected EXE and Serilog DLLs,
and prints the downloaded SHA-256 for auditing. **The upstream release does not
publish a SHA-256 digest, so these checks do not cryptographically authenticate
the archive.** Do not silently update the version or expected size; obtain and
pin a reviewed checksum when available. No runtime download takes place.

After deployment:

```bash
xorriso -version
mono --version
command -v xbox-eeprom-editor
xbox-eeprom-editor
```

The GUI requires an active graphical session and should be exercised on a
deployed machine. An OCI build and a desktop smoke test remain necessary before
this change should be considered production-validated.
