"""CI: is this file a picture that shows something?

    python3 png_check.py picture.png [more.png ...]

Prints the size of each and how many different byte values its pixels have. Exit code 1 when a file is no PNG or
shows one colour only (a browser that started but drew nothing gives such a picture).
"""
import struct
import sys
import zlib

bad = 0
for path in sys.argv[1:]:
    try:
        data = open(path, "rb").read()
        assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
        width, height = struct.unpack(">II", data[16:24])
        at, pixels = 8, b""
        while at < len(data):
            length, kind = struct.unpack(">I4s", data[at:at + 8])
            if kind == b"IDAT":
                pixels += data[at + 8:at + 8 + length]
            at += 12 + length
        values = len(set(zlib.decompress(pixels)))
    except Exception as error:  # a missing or broken file is a result too
        print("%s: %s" % (path, error))
        bad += 1
        continue
    print("%s: %d x %d, %d kB, %d different values" % (path, width, height, len(data) // 1024, values))
    if values <= 8:
        bad += 1
sys.exit(1 if bad else 0)
