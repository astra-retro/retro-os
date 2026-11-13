# Extra retro utilities in Astra Retro OS (PR #11)

The installed OCI image includes three upstream tools, downloaded only at **image build time**.
Their versions and SHA-256 hashes are pinned in `build_files/tools/install-retro-utilities.sh`
and checked before extraction. This prevents a silently changing upstream
release from changing an Astra image build.

| Program | Upstream | Pinned version | Installed command |
| --- | --- | --- | --- |
| PS3Dec | https://github.com/Redrrx/ps3dec | v3.0.0 | `ps3dec` |
| rusty-psn (GUI + CLI) | https://github.com/RainbowCookie32/rusty-psn | v0.7.1 | `rusty-psn`, `rusty-psn-cli` |
| Skyscraper | https://github.com/Gemba/Skyscraper | 3.21.1 | `Skyscraper` |

Both `x86_64` and `aarch64` release artifacts are supported. The rusty-psn
GUI also has a GNOME application launcher. Skyscraper is shipped as an
**extracted XDG AppImage** under `/usr/libexec/retro-os/Skyscraper.AppDir`
so that invoking `Skyscraper` does not require FUSE at runtime. All other
files are installed into immutable `/usr`; per-user settings and game data
remain outside the image in the user's home directory.

Verify after image deployment:

```bash
command -v ps3dec rusty-psn rusty-psn-cli Skyscraper
ps3dec --help
rusty-psn-cli --help
Skyscraper --help
```

The utilities download or process only content explicitly requested by the
user. Astra does not bundle PS3 decryption keys, game images, or PSN content.
Use them only for content you are legally entitled to access and process.

The PR's OCI build must finish successfully before treating these binaries
as validated on Fedora; in particular, check GUI startup for rusty-psn and
Skyscraper in a real desktop session.
