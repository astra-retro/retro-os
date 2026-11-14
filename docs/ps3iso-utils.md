# PS3 ISO Utilities (bucanero/ps3iso-utils)

Astra Retro OS includes all **four native Linux CLI tools** from
[bucanero/ps3iso-utils](https://github.com/bucanero/ps3iso-utils):

| Command | Purpose |
| --- | --- |
| `extractps3iso` | Extract PS3 ISO content into a directory |
| `makeps3iso` | Create a PS3 ISO from a game directory |
| `patchps3iso` | Patch the PS3 ISO firmware version field |
| `splitps3iso` | Split an ISO into 4 GB parts |

At OCI build time, a disposable Fedora build stage clones the upstream source,
checks out the **exact commit** `878090980a9042c61901920fed1b034af215e8c7`,
verifies `HEAD`, then builds all four executables with GCC and Make.
Only the compiled binaries and the upstream GPL license are copied to the
final image. No compilation toolchain, Podman wrapper, runtime download, or
per-user installation is required.

Commands are available directly on `PATH`, under `/usr/bin/`:

```bash
extractps3iso --help
makeps3iso --help
patchps3iso --help
splitps3iso --help
```

Upstream also accepts `/?` for usage details. Note that these are CLI tools:
there is no GNOME desktop launcher. Each command acts on files explicitly
provided by the user.

## Build verification

Run `bash build_files/test-emulation-build-order.sh` to verify the build
stage is pinned and all four tools are copied into `/usr/bin` before the
final `bootc container lint`.

The OCI build must complete successfully before the Fedora 45 binaries are
considered validated. After deployment, check the four help commands on a
supported architecture and exercise them on test game data you are entitled
to process. No PS3 game images, decryption keys, or copyrighted game data
are bundled by Astra Retro OS.
