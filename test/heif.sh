#!/bin/bash
# AVIF / HEIC output: each file of $@ (default: a HEIC photo with EXIF/ICC/XMP, a screenshot, an RGBA PNG)
# goes to .nova (adaptive), then to .png, .avif and .heic, read back with heif-dec. Default mode: lossless
# when the .nova frame is (visible pixels exact), else lossy with at least 44 dB (default quality);
# EXIF values and XMP as in the PNG (exiv2), ICC kept (heif-info; a gain map AVIF: Display P3 by CICP).
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
[ $# -eq 0 ] && set -- ~/photos-nova/IMG_0577.HEIC test/photos/screenshot.png test/corpus/alpha.png
fail=0
for f in "$@"; do
  b=$(basename "$f")
  ./nova encode "$f" $T/t.nova >/dev/null 2>&1 && ./nova decode $T/t.nova $T/t.png >/dev/null 2>&1 || { echo "FAIL $b: nova"; fail=1; continue; }
  for x in avif heic; do
    rm -f $T/d*.png
    ./nova decode $T/t.nova $T/t.$x >/dev/null 2>&1 && heif-dec $T/t.$x $T/d.png >/dev/null 2>&1 || { echo "FAIL $b $x: nova or heif-dec"; fail=1; continue; }
    r=$(uv run -q --with pillow --with numpy python -c "
import numpy as np
from PIL import Image
a = np.asarray(Image.open('$T/t.png').convert('RGBA')).astype(float); d = np.asarray(Image.open('$T/d.png').convert('RGBA')).astype(float)
e = np.abs(a - d)[a[..., 3] > 0]; p = 10 * np.log10(255 ** 2 / max((e ** 2).mean(), 1e-9)); ll = e.max() == 0
print(('ok' if ll or p >= 44 else 'bad') + ' %s %.1f dB' % ('lossless' if ll else 'lossy', p))" 2>&1)
    icc_src=$(uv run -q --with pillow python -c "from PIL import Image; print(int('icc_profile' in Image.open('$T/t.png').info))")
    icc_out=$(heif-info $T/t.$x 2>/dev/null | grep -c "color profile: prof")
    # An AVIF with a gain map says Display P3 by its CICP instead (libavif applies no gain map with an ICC).
    heif-info -d $T/t.$x 2>/dev/null | grep -q "item_type: tmap" && icc_out=$(heif-info -d $T/t.$x | grep -c "colour_primaries: 12" | cut -c1)
    skip='Exif.Image.\(ExifTag\|GPSTag\)'
    if [ "${r%% *}" = ok ] && [ "$icc_src" = "$icc_out" ] && diff <(exiv2 -pa $T/t.png 2>/dev/null | grep -v "$skip" | sort) <(exiv2 -pa $T/t.$x 2>/dev/null | grep -v "$skip" | sort) >/dev/null; then
      echo "OK   $b $x ${r#ok }, $(stat -c %s $T/t.$x) bytes"
    else
      echo "FAIL $b $x: $r icc $icc_src/$icc_out"; fail=1
    fi
  done
done
exit $fail
