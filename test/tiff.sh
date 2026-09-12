#!/bin/bash
# TIFF output: each file of $@ (default: a HEIC with MM EXIF, a screenshot, an RGBA PNG) goes to .nova,
# then to .png and .tif: same pixels (tifffile and PIL), same EXIF values (exiv2), same ICC and XMP.
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
[ $# -eq 0 ] && set -- ~/photos-nova/IMG_0577.HEIC test/photos/screenshot.png test/corpus/alpha.png
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0
for f in "$@"; do
  b=$(basename "$f")
  ./nova encode "$f" $T/t.nova -m lossless >/dev/null 2>&1 && ./nova decode $T/t.nova $T/t.png >/dev/null 2>&1 \
    && ./nova decode $T/t.nova $T/t.tif >/dev/null 2>&1 || { echo "FAIL $b: nova"; fail=1; continue; }
  r=$(uv run -q --with pillow --with tifffile python -c "
import numpy as np, tifffile
from PIL import Image
a = Image.open('$T/t.png'); b = Image.open('$T/t.tif'); t = tifffile.TiffFile('$T/t.tif').pages[0].tags
ok = (np.asarray(a) == tifffile.imread('$T/t.tif')).all() and (np.asarray(a) == np.asarray(b)).all()
ok = ok and a.info.get('icc_profile') == b.info.get('icc_profile')
ok = ok and (a.info.get('XML:com.adobe.xmp') is None) == (700 not in t)
print('ok' if ok else 'bad')" 2>&1)
  # EXIF: same values; pointers and image structure tags differ by nature.
  skip='Exif.Image.\(ExifTag\|GPSTag\|ImageWidth\|ImageLength\|BitsPerSample\|Compression\|Photometric\|StripOffsets\|SamplesPerPixel\|RowsPerStrip\|StripByteCounts\|PlanarConfig\|Predictor\|ExtraSamples\|NewSubfileType\|InterColorProfile\|XMLPacket\)'
  if [ "$r" = ok ] && diff <(exiv2 -pa $T/t.png 2>/dev/null | grep -v "$skip" | sort) <(exiv2 -pa $T/t.tif 2>/dev/null | grep -v "$skip" | sort) >/dev/null; then
    echo "OK   $b  png $(stat -c %s $T/t.png)  tif $(stat -c %s $T/t.tif) bytes"
  else
    echo "FAIL $b: $r"; fail=1
  fi
done
exit $fail
