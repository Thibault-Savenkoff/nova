#!/bin/bash
# Metadata round trip: EXIF (with GPS), XMP, ICC (multi-segment in JPEG), PNG text, Live video,
# HEIC import (libheif: pixels as heif-dec, orientation applied and reset to 1; skipped without heif-enc).
# Run from nova-lisaac/: test/meta.sh
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY="uv run -q --with pillow python"
$PY - "$T" <<'EOF'
import os, sys
from PIL import Image, PngImagePlugin
t = sys.argv[1]
im = Image.new("RGB", (40, 30), (10, 200, 30))
ex = Image.Exif()
ex[0x010F] = "Apple"; ex[0x0110] = "iPhone 17 Pro Max"; ex[0x0112] = 6   # make, model, orientation
ex[0x8825] = {1: "N", 2: (48.0, 51.0, 29.0), 3: "E", 4: (2.0, 17.0, 40.0)}  # GPS
icc = os.urandom(70000)             # > 64 KB: split over 2 APP2 segments
xmp = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF/></x:xmpmeta>'
im.save(f"{t}/a.jpg", exif=ex, icc_profile=icc, xmp=xmp, dpi=(300, 300), comment=b"hello")
info = PngImagePlugin.PngInfo(); info.add_text("Comment", "bonjour")
im.save(f"{t}/b.png", exif=ex, icc_profile=icc[:3000], pnginfo=info)
open(f"{t}/live.mov", "wb").write(os.urandom(100000))
EOF
./nova encode "$T/a.jpg" "$T/a.nova" -live "$T/live.mov"
./nova info "$T/a.nova" | grep -A1 "MDAT\|LIVE"
./nova decode "$T/a.nova" "$T/a_out.png"
cmp "$T/live.mov" "$T/a_out.mov" && echo "OK   live video"
# Re-encoding the decoded PNG keeps the private nvMd chunk (JPEG COM segment here).
./nova encode "$T/a_out.png" "$T/c.nova" > /dev/null
./nova decode "$T/c.nova" "$T/c_out.png" > /dev/null
./nova encode "$T/b.png" "$T/b.nova" > /dev/null
./nova decode "$T/b.nova" "$T/b_out.png" > /dev/null
if command -v heif-enc > /dev/null; then
  # Real ICC here: heif-enc keeps a valid profile only.
  $PY -c "from PIL import Image, ImageCms; import sys; im = Image.open(sys.argv[1]); im.save(sys.argv[2], exif=im.getexif(), xmp=im.info['xmp'], icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes())" "$T/a.jpg" "$T/h.jpg"
  heif-enc -q 95 "$T/h.jpg" -o "$T/h.heic" > /dev/null
  heif-dec "$T/h.heic" "$T/h_ref.png" > /dev/null
  ./nova encode "$T/h.heic" "$T/h.nova" -m lossless > /dev/null
  ./nova decode "$T/h.nova" "$T/h_out.png" > /dev/null
fi
$PY - "$T" <<'EOF'
import sys
from PIL import Image
t = sys.argv[1]
ok = True
import os
pairs = [("a.jpg", "a_out.png"), ("b.png", "b_out.png")]
if os.path.exists(f"{t}/h_out.png"):
    pairs.append(("h.jpg", "h_out.png"))
for src, out in pairs:
    a, b = Image.open(f"{t}/{src}"), Image.open(f"{t}/{out}")
    b.load()
    ea, eb = a.getexif(), b.getexif()
    if src == "h.jpg":
        ea[0x0112] = 1      # pixels come turned: the orientation tag is reset
    checks = {
        "exif": dict(ea) == dict(eb) and ea.get_ifd(0x8825) == eb.get_ifd(0x8825) and len(ea) > 0,
        "icc": a.info.get("icc_profile") == b.info.get("icc_profile") != None,
    }
    if src == "h.jpg":
        checks["xmp"] = a.info.get("xmp") == b.info.get("xmp") != None
        checks["pixels == heif-dec"] = Image.open(f"{t}/h_ref.png").convert("RGB").tobytes() == b.convert("RGB").tobytes()
    elif src == "a.jpg":
        checks["xmp"] = a.info.get("xmp") == b.info.get("xmp") != None
        checks["dpi"] = [round(v) for v in b.info.get("dpi", (0, 0))] == [300, 300]
        c = open(f"{t}/c_out.png", "rb").read()
        checks["COM kept (nvMd, after re-encode)"] = c.count(b"nvMdCOM hello") == 1
    else:
        checks["text"] = b.info.get("Comment") == "bonjour"
    for k, v in checks.items():
        print("OK  " if v else "FAIL", src, k)
        ok &= v
sys.exit(0 if ok else 1)
EOF
