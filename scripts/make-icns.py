#!/usr/bin/env python3
"""Package PNG icon representations into a standard macOS ICNS container."""

from pathlib import Path
import struct
import sys


if len(sys.argv) != 3:
    raise SystemExit("usage: make-icns.py iconset-directory output.icns")

iconset = Path(sys.argv[1])
output = Path(sys.argv[2])
representations = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

chunks = []
for chunk_type, filename in representations:
    data = (iconset / filename).read_bytes()
    chunks.append(chunk_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

payload = b"".join(chunks)
output.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
