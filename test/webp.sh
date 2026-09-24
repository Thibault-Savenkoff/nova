#!/bin/bash
# WebP output: each file of $@ (default: a HEIC photo with EXIF/ICC/XMP, a screenshot, an RGBA PNG) goes to
# .yaif (adaptive), then to .png and .webp. Default mode: lossless when the .yaif frame is (visible pixels
# exact), else lossy (PSNR >= 38 dB at q 90). Size within 5 % of PIL's (same libwebp); EXIF values, ICC
# and XMP as in the PNG. Also: -m lossy forced on a lossless .yaif.
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
[ $# -eq 0 ] && set -- ~/photos-yaif/IMG_0577.HEIC test/photos/screenshot.png test/corpus/alpha.png
fail=0
for f in "$@"; do
  b=$(basename "$f")
  ./yaif encode "$f" $T/t.yaif >/dev/null 2>&1 && ./yaif decode $T/t.yaif $T/t.png >/dev/null 2>&1 \
    && ./yaif decode $T/t.yaif $T/t.webp >/dev/null 2>&1 && ./yaif decode $T/t.yaif $T/f.webp -m lossy -q 75 >/dev/null 2>&1 \
    || { echo "FAIL $b: yaif"; fail=1; continue; }
  r=$(uv run -q --with pillow --with numpy python -c "
import io, os, numpy as np
from PIL import Image
a = Image.open('$T/t.png'); w = Image.open('$T/t.webp'); w.load(); f = Image.open('$T/f.webp'); f.load()
A = np.asarray(a.convert('RGBA')).astype(float); W = np.asarray(w.convert('RGBA')).astype(float)
d = np.abs(A - W)[A[..., 3] > 0]; lossless = bool(d.max() == 0); psnr = 10 * np.log10(255 ** 2 / max((d ** 2).mean(), 1e-9))
buf = io.BytesIO(); a.save(buf, 'WEBP', lossless=lossless, quality=90, method=4); s, ps = os.path.getsize('$T/t.webp'), len(buf.getvalue())
ok = (lossless or psnr >= 38) and s <= ps * 1.05 + 500 and a.info.get('icc_profile') == w.info.get('icc_profile')
ok = ok and ('XML:com.adobe.xmp' in a.info) == bool(w.info.get('xmp')) and bool((np.asarray(f.convert('RGBA')).astype(float) != A)[A[..., 3] > 0].any())
print(('ok' if ok else 'bad') + ' %s %d bytes (PIL %d), %.1f dB' % ('lossless' if lossless else 'lossy', s, ps, psnr))" 2>&1)
  skip='Exif.Image.\(ExifTag\|GPSTag\)'
  if [ "${r%% *}" = ok ] && diff <(exiv2 -pa $T/t.png 2>/dev/null | grep -v "$skip" | sort) <(exiv2 -pa $T/t.webp 2>/dev/null | grep -v "$skip" | sort) >/dev/null; then
    echo "OK   $b ${r#ok }"
  else
    echo "FAIL $b: $r"; fail=1
  fi
done
exit $fail
