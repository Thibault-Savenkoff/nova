#!/bin/bash
# JPEG output: each file of $@ (default: a HEIC with EXIF/ICC/XMP, a screenshot, an RGBA PNG, odd sizes)
# goes to .nova (lossless), then to .png and to .jpg at q 75 and 90. The JPEG must decode (PIL), be no
# bigger than libjpeg's (optimised Huffman, same subsampling) by more than 1 % at no more than 0.2 dB
# less PSNR (from 4096 pixels: on a few pixels PSNR is one rounding), and keep the EXIF values, ICC
# and XMP of the PNG. An Ultra HDR JPEG (HEIC with a gain map) is measured on its primary image; the
# gain map is the other JPEG in its MPF index (test/hdr.sh checks it).
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
uv run -q --with pillow python -c "
from PIL import Image
Image.new('RGB', (1, 1), (200, 30, 90)).save('$T/one.png')
Image.radial_gradient('L').resize((37, 19)).convert('RGB').save('$T/odd.png')"
[ $# -eq 0 ] && set -- ~/photos-nova/IMG_0577.HEIC test/photos/screenshot.png test/corpus/alpha.png $T/one.png $T/odd.png
fail=0
for f in "$@"; do
  b=$(basename "$f")
  ./nova encode "$f" $T/t.nova -m lossless >/dev/null 2>&1 && ./nova decode $T/t.nova $T/t.png >/dev/null 2>&1 || { echo "FAIL $b: nova"; fail=1; continue; }
  for q in 75 90; do
    ./nova decode $T/t.nova $T/t.jpg -q $q >/dev/null 2>&1 || { echo "FAIL $b q$q: decode"; fail=1; continue; }
    r=$(uv run -q --with pillow --with numpy python -c "
import io, os, numpy as np
from PIL import Image
a = np.asarray(Image.open('$T/t.png').convert('RGBA')).astype(float); al = a[..., 3:] / 255
ref = a[..., :3] * al + 255 * (1 - al)
def psnr(im): return 10 * np.log10(255 ** 2 / max(((np.asarray(im.convert('RGB')).astype(float) - ref) ** 2).mean(), 1e-9))
n = Image.open('$T/t.jpg'); n.load()
buf = io.BytesIO(); Image.fromarray(ref.round().astype('uint8')).save(buf, 'JPEG', quality=$q, optimize=True, subsampling=0 if $q >= 90 else 2)
mp = n._getmp() or {}; e = mp.get(0xB002, [{}])
s, ls = e[0].get('Size', os.path.getsize('$T/t.jpg')), len(buf.getvalue()); p, lp = psnr(n), psnr(Image.open(buf))
p0 = Image.open('$T/t.png').info
ok = s <= ls * 1.01 + 700 and (p >= lp - 0.2 or a.shape[0] * a.shape[1] < 4096) and p0.get('icc_profile') == n.info.get('icc_profile') and ('XML:com.adobe.xmp' in p0) == ('xmp' in n.info)
print(('ok' if ok else 'bad') + ' %d bytes %.2f dB (libjpeg %d bytes %.2f dB)' % (s, p, ls, lp) + (' + gain map %d bytes' % e[1]['Size'] if len(e) > 1 else ''))" 2>&1)
    skip='Exif.Image.\(ExifTag\|GPSTag\)\|Xmp.hdrgm\|Xmp.Container'
    if [ "${r%% *}" = ok ] && diff <(exiv2 -pa $T/t.png 2>/dev/null | grep -v "$skip" | sort) <(exiv2 -pa $T/t.jpg 2>/dev/null | grep -v "$skip" | sort) >/dev/null; then
      echo "OK   $b q$q ${r#ok }"
    else
      echo "FAIL $b q$q: $r"; fail=1
    fi
  done
done
exit $fail
