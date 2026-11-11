#!/usr/bin/env python3
"""Preserve GNOME Shell's GResource while branding its greeter backdrop."""
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

RESOURCE = Path("/usr/share/gnome-shell/gnome-shell-theme.gresource")
WALLPAPER = Path("/usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png")
PREFIX = "/org/gnome/shell/theme/"
CSS = ("gnome-shell-dark.css", "gnome-shell-light.css", "gnome-shell-high-contrast.css")
ADDITION = """
/* Astra Retro OS GDM greeter background only; keep login form untouched. */
#lockDialogGroup {
  background-color: #171923;
  background-image: url("file:///usr/share/backgrounds/astra-retro-os/wallpaper-pixel-art.png");
  background-repeat: no-repeat;
  background-position: center center;
  background-size: cover;
}
"""

def call(*args):
    return subprocess.check_output(args)

def main():
    if not WALLPAPER.is_file() or WALLPAPER.stat().st_size < 1024:
        raise SystemExit("ERROR: Pixel-art wallpaper missing from installed OCI")
    if not RESOURCE.is_file():
        raise SystemExit("ERROR: GNOME Shell theme resource is missing")
    members = call("gresource", "list", str(RESOURCE)).decode().splitlines()
    if len(members) < 4 or any(
        not name.startswith(PREFIX) or "/" in name[len(PREFIX):]
        for name in members
    ):
        raise SystemExit("ERROR: Unknown GNOME theme GResource layout")

    with tempfile.TemporaryDirectory(prefix="astra-gdm-") as workdir:
        tmp = Path(workdir)
        for member in members:
            name = member.removeprefix(PREFIX)
            data = call("gresource", "extract", str(RESOURCE), member)
            if not data:
                raise SystemExit(f"ERROR: Empty vendor GResource: {member}")
            (tmp / name).write_bytes(data)

        for name in CSS:
            target = tmp / name
            if not target.is_file():
                raise SystemExit(f"ERROR: Required GNOME stylesheet missing: {name}")
            text = target.read_text()
            if "#lockDialogGroup" not in text:
                raise SystemExit(f"ERROR: Incompatible GNOME greeter stylesheet: {name}")
            target.write_text(text + ADDITION)

        root = ET.Element("gresources")
        group = ET.SubElement(root, "gresource", prefix=PREFIX.removesuffix("/"))
        for member in sorted(members):
            ET.SubElement(group, "file").text = member.removeprefix(PREFIX)
        manifest = tmp / "astra-gdm.xml"
        ET.ElementTree(root).write(manifest, encoding="utf-8", xml_declaration=True)
        output = tmp / "patched.gresource"
        subprocess.run(
            ["glib-compile-resources", f"--sourcedir={tmp}",
             f"--target={output}", str(manifest)], check=True)
        actual = call("gresource", "list", str(output)).decode().splitlines()
        if sorted(actual) != sorted(members):
            raise SystemExit("ERROR: Compiled GNOME theme resource differs from vendor")
        for name in CSS:
            data = call("gresource", "extract", str(output), PREFIX + name)
            if b"wallpaper-pixel-art.png" not in data:
                raise SystemExit(f"ERROR: Greeter wallpaper missing from {name}")

        # Atomic replacement of a vendor file in the OCI build layer, not at
        # runtime on an immutable /usr; upgrades rebuild from the base image.
        final = RESOURCE.with_name(RESOURCE.name + ".astra-tmp")
        final.write_bytes(output.read_bytes())
        final.chmod(0o644)
        final.replace(RESOURCE)
        print("Astra GNOME Shell greeter resource successfully rebuilt")

if __name__ == "__main__":
    main()
