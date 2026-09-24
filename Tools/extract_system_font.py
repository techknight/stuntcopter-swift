#!/usr/bin/env python3
"""Extract the Chicago 12 'FONT' resource (ID 12) from a System 6 disk image.

    .venv/bin/python Tools/extract_system_font.py <System Startup.img> Resources/Chicago12.FONT

The output is the raw FONT resource data (Inside Macintosh I-227). Requires `machfs`.
"""
import struct
import sys

import machfs

from make_reference_disk import read_disk_image


def resources(fork):
    data_off, map_off = struct.unpack(">II", fork[0:8])
    type_list = map_off + struct.unpack(">H", fork[map_off + 24:map_off + 26])[0]
    for t in range(struct.unpack(">H", fork[type_list:type_list + 2])[0] + 1):
        te = type_list + 2 + 8 * t
        rtype = fork[te:te + 4]
        count, ref_off = struct.unpack(">HH", fork[te + 4:te + 8])
        for k in range(count + 1):
            re = type_list + ref_off + 12 * k
            rid = struct.unpack(">h", fork[re:re + 2])[0]
            off = data_off + int.from_bytes(fork[re + 5:re + 8], "big")
            length = struct.unpack(">I", fork[off:off + 4])[0]
            yield rtype, rid, fork[off + 4:off + 4 + length]


def main(system_image, out_path, font_id=12):
    vol = machfs.Volume()
    vol.read(read_disk_image(system_image))
    fork = vol["System Folder"]["System"].rsrc
    for rtype, rid, data in resources(fork):
        if rtype == b"FONT" and rid == int(font_id):
            open(out_path, "wb").write(data)
            print(f"wrote {out_path} ({len(data)} bytes)")
            return
    sys.exit(f"FONT {font_id} not found")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
