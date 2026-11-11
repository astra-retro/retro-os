#!/usr/bin/env python3
"""Make a GNOME circular-safe avatar using the existing Astra SVG artwork."""
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

SOURCE = Path(sys.argv[1])
DEST = Path("/usr/share/pixmaps/faces/astra-retro-os.png")
TEMPLATE_ROOT = Path("/etc/accountsservice/user-templates")
VENDOR_ROOT = Path("/usr/share/accountsservice/user-templates")
SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)

def main():
    if not SOURCE.is_file() or SOURCE.stat().st_size < 100:
        raise SystemExit(f"Missing original Astra SVG logo: {SOURCE}")
    source = ET.parse(SOURCE).getroot()
    root = ET.Element(f"{{{SVG_NS}}}svg", {"width":"512", "height":"512",
        "viewBox":"0 0 512 512"})
    ET.SubElement(root, f"{{{SVG_NS}}}circle", {
        "cx":"256", "cy":"256", "r":"254", "fill":"#090A20"})
    # Scale the entire original 512px logo to 72%: all original square
    # corners remain INSIDE the 512px circular crop used by GNOME/GDM.
    group = ET.SubElement(root, f"{{{SVG_NS}}}g", {
        "transform":"translate(71.68 71.68) scale(0.72)"})
    for child in source:
        group.append(child)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="astra-avatar-") as work:
        svg = Path(work) / "avatar.svg"
        svg.write_bytes(ET.tostring(root, encoding="utf-8", xml_declaration=True))
        subprocess.run(["rsvg-convert", "-w", "512", "-h", "512",
                        "-o", str(DEST), str(svg)], check=True)
    if DEST.stat().st_size < 1024 or DEST.read_bytes()[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("Invalid generated circular Astra avatar PNG")
    DEST.chmod(0o644)

    # Use the AccountsService-supported templates for both ordinary and
    # administrator accounts. Preserve session, locale and other options.
    TEMPLATE_ROOT.mkdir(parents=True, exist_ok=True)
    for name in ("standard", "administrator"):
        template = TEMPLATE_ROOT / name
        if not template.exists():
            source_template = VENDOR_ROOT / name
            # Minimal template is valid when the vendor ships no example;
            # do not fail an otherwise working OS image on that condition.
            if source_template.is_file():
                template.write_bytes(source_template.read_bytes())
            else:
                template.write_text("[User]\n")
        original = template.read_text()
        if not re.search(r"(?m)^\[User\]\s*$", original):
            raise SystemExit(f"AccountsService user section missing: {template}")
        # Don't override a distribution administrator's explicit avatar.
        if re.search(r"(?m)^Icon\s*=", original):
            print(f"Existing avatar template preserved: {template}")
            continue
        # Insert exactly once, without relying on regex replacement escapes.
        template.write_text(original.replace("[User]", f"[User]\nIcon={DEST}", 1))
        template.chmod(0o644)
        print(f"Configured default AccountsService avatar: {template}")

if __name__ == "__main__":
    main()
