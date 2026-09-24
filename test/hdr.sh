#!/bin/bash
# HDR gain map: each HEIC of $@ (default: an iPhone photo, lossy, and a screenshot, lossless) goes to
# .yaif with its gain map (GMAP). Checks:
# - the gain map decoded by node (docs/yaif_decode.js) is the one yaif decodes, byte for byte;
# - the Ultra HDR JPEG, read back by libuhdr (ImageMagick UHDR, PQ output), is the -hdr PNG
#   (mean error < 1 on 8 bits: the two apply the gain map independently);
# - the same for the JavaScript Ultra HDR builder, on JPEGs made by ImageMagick (< 2: JPEG loss);
# - the -hdr AVIF, read back by heif-dec, is the -hdr PNG (< 2), tagged PQ, with clli and mdcv;
# - the plain AVIF of a lossy .yaif has the gain map (tmap item), and its SDR image, read back by
#   heif-dec, is the PNG (< 2); a lossless one stays a lossless AVIF, without it.
#   (Its HDR rendition was checked once with libavif's own avifImageApplyGainMap: within 1 of the
#   -hdr PNG; the check needs avif.h, which is not installed here.)
# - the -hdr TIFF (half floats, linear BT.709) is the -hdr PNG turned linear (p99 relative error < 1 %).
# Needs node, ImageMagick 7 with UHDR (libuhdr) and heif-dec.
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
[ $# -eq 0 ] && set -- ~/photos-yaif/IMG_1045.HEIC ~/photos-yaif/IMG_1036.HEIC
fail=0
mad() {  # mean absolute difference of two images, 8-bit RGB
  uv run -q --with pillow --with numpy python -c "
import numpy as np; from PIL import Image
a, b = (np.asarray(Image.open(f).convert('RGB'), float) for f in ('$1', '$2'))
print('%.2f' % (np.abs(a - b).mean() if a.shape == b.shape else 999))"
}
check() {  # $1 label, $2 value, $3 limit
  if awk "BEGIN { exit !($2 < $3) }"; then echo "OK   $1 $2"; else echo "FAIL $1 $2 (limit $3)"; fail=1; fi
}
for f in "$@"; do
  b=$(basename "$f")
  ./yaif encode "$f" $T/t.yaif >$T/enc.txt 2>&1 && ./yaif info $T/t.yaif | grep -q GMAP || { echo "FAIL $b: no GMAP"; fail=1; continue; }
  YAIF_GAINMAP=$T/gm.png ./yaif decode $T/t.yaif $T/t.png >/dev/null 2>&1
  r=$(node test/uhdr_js.js $T/t.yaif $T/gm.raw 2>&1) || { echo "FAIL $b: $r"; fail=1; continue; }
  ok=$(uv run -q --with pillow --with numpy python -c "
import numpy as np; from PIL import Image
a = np.asarray(Image.open('$T/gm.png').convert('RGBA')).ravel(); b = np.fromfile('$T/gm.raw', np.uint8)
print('ok' if a.shape == b.shape and (a == b).all() else 'bad')")
  [ "$ok" = ok ] && echo "OK   $b gain map, JS = yaif ($r)" || { echo "FAIL $b gain map JS/yaif"; fail=1; }
  ./yaif decode $T/t.yaif $T/hdr.png -hdr >/dev/null 2>&1 && ./yaif decode $T/t.yaif $T/u.jpg >/dev/null 2>&1 || { echo "FAIL $b: yaif HDR export"; fail=1; continue; }
  magick -define uhdr:output-color-transfer=pq UHDR:$T/u.jpg -depth 16 $T/u.png 2>/dev/null
  check "$b Ultra HDR (yaif) vs -hdr PNG:" "$(mad $T/u.png $T/hdr.png)" 1
  magick $T/t.png -quality 95 $T/p.jpg && magick $T/gm.png -quality 95 $T/g.jpg
  node test/uhdr_js.js $T/t.yaif $T/gm.raw $T/p.jpg $T/g.jpg $T/j.jpg >/dev/null
  magick -define uhdr:output-color-transfer=pq UHDR:$T/j.jpg -depth 16 $T/j.png 2>/dev/null
  check "$b Ultra HDR (JS)   vs -hdr PNG:" "$(mad $T/j.png $T/hdr.png)" 2
  ./yaif decode $T/t.yaif $T/h.avif -hdr >/dev/null 2>&1 && heif-dec $T/h.avif $T/a.png >/dev/null 2>&1
  heif-info -d $T/h.avif | grep -q "transfer_characteristics: 16" || { echo "FAIL $b AVIF not tagged PQ"; fail=1; }
  check "$b -hdr AVIF        vs -hdr PNG:" "$(mad $T/a.png $T/hdr.png)" 2
  [ "$(heif-info -d $T/h.avif | grep -c 'Box: clli\|Box: mdcv')" = 2 ] || { echo "FAIL $b -hdr AVIF without clli/mdcv"; fail=1; }
  ./yaif decode $T/t.yaif $T/g.avif >/dev/null 2>&1 && heif-dec $T/g.avif $T/s.png >/dev/null 2>&1
  lossy=$(grep -c "(lossy" $T/enc.txt)
  [ "$(heif-info -d $T/g.avif | grep -c 'item_type: tmap')" = "$lossy" ] || { echo "FAIL $b AVIF gain map: expected $lossy tmap item"; fail=1; }
  check "$b gain map AVIF SDR vs PNG:  " "$(mad $T/s.png $T/t.png)" 2
  ./yaif decode $T/t.yaif $T/h.tif -hdr >/dev/null 2>&1 || { echo "FAIL $b: yaif HDR TIFF"; fail=1; continue; }
  check "$b -hdr TIFF (rel. p99) vs PNG:" "$(uv run -q --with tifffile --with numpy python -c "
import tifffile, numpy as np, zlib, struct
T = tifffile.imread('$T/h.tif').astype(float)
d = open('$T/hdr.png', 'rb').read(); p = 8; z = b''
while p < len(d):
    n = struct.unpack('>I', d[p:p + 4])[0]
    if d[p + 4:p + 8] == b'IHDR': w, h = struct.unpack('>II', d[p + 8:p + 16])
    if d[p + 4:p + 8] == b'cICP': p3 = d[p + 8] == 12
    if d[p + 4:p + 8] == b'IDAT': z += d[p + 8:p + 8 + n]
    p += 12 + n
E = np.frombuffer(zlib.decompress(z), np.uint8).reshape(h, w * 6 + 1)[:, 1:].reshape(h, w, 3, 2)
E = (E[..., 0] * 256.0 + E[..., 1]) / 65535 ** 1
Ep = E ** (1 / 78.84375)
L = (np.maximum(Ep - 0.8359375, 0) / (18.8515625 - 18.6875 * Ep)) ** (1 / 0.1593017578125) * 10000 / 203
if p3: L = L @ np.array([[1.2249401, -0.2249404, 0], [-0.0420569, 1.0420571, 0], [-0.0196376, -0.0786361, 1.0982735]]).T
m = T.min(axis=2) > 0.001
print('%.4f' % (np.percentile(np.abs(T - L)[m] / np.maximum(np.abs(L[m]), 0.01), 99) if T.shape == L.shape else 999))")" 0.01
done
exit $fail
