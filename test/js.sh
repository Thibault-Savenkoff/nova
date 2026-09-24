#!/bin/bash
# DEC=command replaces the node decoder (test/libyaif.sh: libyaifdec, the C decoder).
# JavaScript decoder (docs/yaif_decode.js): each file of $@ (default: the corpus images, an animation,
# a 2800x2000 photo crop: several stripes, PREV) goes to .yaif at every level, then is decoded by yaif
# and by node: the pixels must be the same byte for byte (frames and PREV thumbnail).
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
if [ $# -eq 0 ]; then
  ./yaif encode ~/photos-yaif/IMG_0577.HEIC $T/h.yaif -m lossless -l 1 >/dev/null 2>&1 && ./yaif decode $T/h.yaif $T/h.png >/dev/null 2>&1
  uv run -q --with pillow python -c "
import random
from PIL import Image
Image.open('$T/h.png').convert('RGB').crop((0, 0, 2800, 2000)).save('$T/photo.png')
random.seed(1)
im = Image.new('RGB', (64, 48)); im.putdata([(random.randrange(256), x * 4, y * 5) for y in range(48) for x in range(64)])
im.save('$T/a0.png'); im.putpixel((10, 7), (1, 2, 3)); im.save('$T/a1.png'); im.save('$T/a2.png')
for y in range(5, 40):
    for x in range(3, 60): im.putpixel((x, y), (x, y, x ^ y))
im.save('$T/a3.png')"
  set -- test/corpus/* "$T/a0.png $T/a1.png $T/a2.png $T/a3.png" $T/photo.png
fi
fail=0
cmp_js() {  # $1 yaif file, $2 label, $3 "preview" or ""
  if [ "$3" = preview ]; then ./yaif preview "$1" $T/ref.png >/dev/null 2>&1 || { echo "SKIP $2 (no preview)"; return; }
  else rm -f $T/ref*.png; ./yaif decode "$1" $T/ref.png >/dev/null 2>&1 || { echo "FAIL $2: yaif"; fail=1; return; }; fi
  r=$(${DEC:-node test/js_dump.js} "$1" $T/js.raw $3 2>&1) || { echo "FAIL $2: $r"; fail=1; return; }
  ok=$(uv run -q --with pillow --with numpy python -c "
import glob, numpy as np
from PIL import Image
fs = sorted(glob.glob('$T/ref_*.png')) or ['$T/ref.png']
ref = np.concatenate([np.asarray(Image.open(f).convert('RGBA')).ravel() for f in fs])
js = np.fromfile('$T/js.raw', np.uint8)
a = Image.open(fs[0]).mode
if a != 'RGBA': ref = ref.reshape(-1, 4)[:, :3].ravel(); js = js.reshape(-1, 4)[:, :3].ravel()
print('ok' if ref.shape == js.shape and (ref == js).all() else 'bad %s %s %d' % (ref.shape, js.shape, (ref != js).sum() if ref.shape == js.shape else -1))")
  if [ "$ok" = ok ]; then echo "OK   $2  $r"; else echo "FAIL $2: $ok"; fail=1; fi
}
for f in "$@"; do
  b=$(basename ${f%% *}); [ "$f" != "${f%% *}" ] && b="$b (animation)"
  for m in "-m lossless -l 1" "-m lossless -l 2" "-m lossless -l 3" "-m lossless -l 4" "-l 5" "-m lossless -l 0" "-m lossy -l 3 -e 2" "-m lossy -l 4 -e 1"; do
    ./yaif encode $f $T/t.yaif $m >/dev/null 2>&1 || { echo "SKIP $b $m"; continue; }
    cmp_js $T/t.yaif "$b $m"
    case $b in photo.png) cmp_js $T/t.yaif "$b $m PREV" preview;; esac
  done
done
exit $fail
