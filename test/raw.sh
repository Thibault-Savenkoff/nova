#!/bin/bash
# RAW (level 6): each file of $@ (default ~/photos-nova/cr3/*.CR3) goes to .nova then to DNG; LibRaw
# must read the same sensor frame and the same parameters (levels, colour, white balance, EXIF) from
# the DNG as from the source. Prints NOVA size vs the source file, encode and decode times.
# Run from nova-lisaac/: test/raw.sh [files...]
cd "$(dirname "$0")/.."
export LC_ALL=C
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gcc -O2 -o "$T/rawdump" test/rawdump.c -ldl || exit 1
[ $# -eq 0 ] && set -- ~/photos-nova/cr3/*.CR3
fail=0
for f in "$@"; do
  t0=$(date +%s.%N)
  ./nova encode "$f" "$T/r.nova" > /dev/null || { echo "FAIL $f: encode"; fail=1; continue; }
  t1=$(date +%s.%N)
  ./nova decode "$T/r.nova" "$T/r.dng" > /dev/null || { echo "FAIL $f: decode"; fail=1; continue; }
  t2=$(date +%s.%N)
  "$T/rawdump" "$f" "$T/ref.bin" > "$T/ref.txt"
  "$T/rawdump" "$T/r.dng" "$T/dec.bin" > "$T/dec.txt"
  s=$(stat -c %s "$f"); n=$(stat -c %s "$T/r.nova")
  r=$(printf "%s  %d -> %d bytes (%d %%)  encode %.1f s  decode %.1f s" "$(basename "$f")" $s $n $((n * 100 / s)) $(echo "$t1 - $t0" | bc) $(echo "$t2 - $t1" | bc))
  if ! cmp -s "$T/ref.bin" "$T/dec.bin"; then echo "FAIL $r: frame differs"; fail=1
  elif ! cmp -s "$T/ref.txt" "$T/dec.txt"; then echo "FAIL $r: parameters differ"; diff "$T/ref.txt" "$T/dec.txt"; fail=1
  else echo "OK   $r"; fi
done
# Metadata: the MDAT blocks must be the CMT1-4 boxes of the CR3, byte for byte.
f=$1
case "$f" in *.CR3|*.cr3)
  ./nova encode "$f" "$T/r.nova" > /dev/null
  python3 - "$f" "$T/r.nova" <<'PY' && echo "OK   $(basename "$f") CMT1-4 kept" || { echo "FAIL $(basename "$f") metadata"; fail=1; }
import sys, struct
src = open(sys.argv[1], 'rb').read(1 << 20)
cmt = {}
for k in (b'CMT1', b'CMT2', b'CMT3', b'CMT4'):
    i = src.find(k)
    cmt[k] = src[i + 4:i - 4 + struct.unpack('>I', src[i - 4:i])[0]]
d, p, got = open(sys.argv[2], 'rb').read(), 9, {}
while p + 12 <= len(d):
    t, n = d[p:p + 4], struct.unpack('>I', d[p + 4:p + 8])[0]
    if t == b'MDAT': got[d[p + 8:p + 12]] = d[p + 12:p + 8 + n]
    p += n + 12
sys.exit(got != cmt)
PY
esac
# Rendering: darktable must develop the DNG like the source (it uses the real white level of the camera).
if command -v darktable-cli > /dev/null; then
  ./nova decode "$T/r.nova" "$T/b.dng" > /dev/null
  ext=${f##*.}
  cp "$f" "$T/a.$ext"
  for x in "a.$ext" b.dng; do
    darktable-cli "$T/$x" "$T/${x%.*}.png" --width 800 --core --configdir "$T/dtconf" --library :memory: > /dev/null 2>&1
  done
  uv run -q --with numpy --with pillow python -c "
import sys, numpy as np; from PIL import Image
a = np.asarray(Image.open(sys.argv[1]).convert('RGB'), float); b = np.asarray(Image.open(sys.argv[2]).convert('RGB'), float)
d = np.abs(a - b).mean(); print(round(d, 3)); sys.exit(int(d > 0.5))" "$T/a.png" "$T/b.png" > "$T/d.txt" \
    && echo "OK   $(basename "$f") darktable renders the DNG like the source (mean diff $(cat "$T/d.txt"))" \
    || { echo "FAIL $(basename "$f") darktable rendering differs (mean diff $(cat "$T/d.txt"))"; fail=1; }
fi
# Development (nova decode to .tif/.png): the same image as LibRaw's on the source file (test/develop.c,
# same settings), the source EXIF in both files, and a PREV thumbnail.
cc -O2 -Ithird_party/libraw -o "$T/develop" test/develop.c -l:libraw_r.so.25 -lm || exit 1
./nova encode "$f" "$T/r.nova" > /dev/null
./nova decode "$T/r.nova" "$T/d.tif" > /dev/null && ./nova decode "$T/r.nova" "$T/d.png" > /dev/null && ./nova preview "$T/r.nova" "$T/p.png" > /dev/null \
  && "$T/develop" "$f" "$T/ref.ppm" && uv run -q --with numpy --with pillow --with tifffile python -c "
import sys, numpy as np, tifffile; from PIL import Image
d = open(sys.argv[1], 'rb').read().split(b'\n', 3); w, h = map(int, d[1].split())
a = np.frombuffer(d[3], '>u2').reshape(h, w, 3).astype(int); t = tifffile.imread(sys.argv[2]).astype(int)
p = np.asarray(Image.open(sys.argv[3])).astype(int)
sys.exit(int(a.shape != t.shape or (a != t).any() or np.abs(p - (t * 255 + 32767) // 65535).max() > 1 or max(Image.open(sys.argv[4]).size) != 512))" \
  "$T/ref.ppm" "$T/d.tif" "$T/d.png" "$T/p.png" \
  && (for x in d.tif d.png; do [ "$(exiv2 -g Exif.Photo.DateTimeOriginal -Pv "$T/$x")" = "$(exiv2 -g Exif.Photo.DateTimeOriginal -Pv "$f")" ] || exit 1; done) \
  && echo "OK   $(basename "$f") developed .tif/.png = LibRaw on the source, EXIF kept, 512 px PREV" \
  || { echo "FAIL $(basename "$f") development"; fail=1; }
# darktable look: same image as test/develop.c with look 1.
./nova decode "$T/r.nova" "$T/k.tif" -look darktable > /dev/null && "$T/develop" "$f" "$T/refk.ppm" 1 && uv run -q --with numpy --with tifffile python -c "
import sys, numpy as np, tifffile
d = open(sys.argv[1], 'rb').read().split(b'\n', 3); w, h = map(int, d[1].split())
sys.exit(int((np.frombuffer(d[3], '>u2').reshape(h, w, 3) != tifffile.imread(sys.argv[2])).any()))" "$T/refk.ppm" "$T/k.tif" \
  && echo "OK   $(basename "$f") -look darktable = LibRaw + darktable curve" || { echo "FAIL $(basename "$f") -look darktable"; fail=1; }
exit $fail
