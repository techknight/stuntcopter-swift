#!/usr/bin/env python3
"""Build an 800K System 6 boot floppy that starts the original StuntCopter 1.5.

The disk contains System + Finder (from a System 6.0.8 "System Startup" disk
image you supply) and the 1987 StuntCopter application rebuilt from
original/StuntCopter1.5.AppleDouble. The boot blocks name StuntCopter as the
startup shell, so an emulated Mac Plus boots straight into the game.

    python3 -m venv .venv && .venv/bin/pip install machfs
    .venv/bin/python Tools/make_reference_disk.py <System Startup.img> build/reference/StuntCopter-boot.dsk

Requires the `machfs` package (https://github.com/elliotnunn/machfs).
"""
import struct
import sys

import machfs

DISK_SIZE = 800 * 1024
DC42_HEADER = 84


def read_disk_image(path):
    """Returns the raw sectors of a raw or DiskCopy 4.2 image."""
    data = open(path, "rb").read()
    if len(data) > DC42_HEADER and data[0x52:0x54] == b"\x01\x00":   # DiskCopy 4.2 private word
        size = struct.unpack(">I", data[0x40:0x44])[0]
        return data[DC42_HEADER:DC42_HEADER + size]
    return data


def apple_double(path):
    """Returns (finder_info, resource_fork) from an AppleDouble file."""
    d = open(path, "rb").read()
    assert d[:4] == b"\x00\x05\x16\x07", "not AppleDouble"
    finfo, rsrc = b"", b""
    for i in range(struct.unpack(">H", d[24:26])[0]):
        eid, off, ln = struct.unpack(">III", d[26 + 12 * i:38 + 12 * i])
        if eid == 9:
            finfo = d[off:off + ln]
        elif eid == 2:
            rsrc = d[off:off + ln]
    return finfo, rsrc


def main(system_image, out_path, app_appledouble="original/StuntCopter1.5.AppleDouble"):
    src = machfs.Volume()
    src.read(read_disk_image(system_image))
    sys_folder = src["System Folder"]

    vol = machfs.Volume()
    vol.name = "StuntCopter"
    folder = machfs.Folder()
    vol["System Folder"] = folder
    for name in ("System", "Finder"):
        folder[name] = sys_folder[name]

    finfo, rsrc = apple_double(app_appledouble)
    app = machfs.File()
    app.type, app.creator = finfo[0:4], finfo[4:8]
    app.flags = struct.unpack(">H", finfo[8:10])[0]
    app.rsrc = rsrc
    folder["StuntCopter"] = app      # the shell must live in the blessed folder
    vol["StuntCopter"] = machfs.File()
    vol["StuntCopter"].type, vol["StuntCopter"].creator = app.type, app.creator
    vol["StuntCopter"].flags, vol["StuntCopter"].rsrc = app.flags, rsrc

    # machfs builds the boot blocks from the System's 'boot' 1 resource; startapp
    # sets the startup application (bbHelloName) so the Mac boots into the game.
    image = vol.write(size=DISK_SIZE, align=512, desktopdb=True, bootable=True,
                      startapp=("System Folder", "StuntCopter"))
    with open(out_path, "wb") as f:
        f.write(image)
    print(f"wrote {out_path} ({len(image)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
