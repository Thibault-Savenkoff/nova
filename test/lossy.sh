#!/bin/bash
# Lossy checks. Near-lossless (level 3): max error <= eps, alpha exact. Wavelet (level 5, q 90):
# the decoder rebuilds exactly the encoder's reconstruction (YAIF_RECON; also at q 50, chroma filter
# at full strength), alpha exact (alpha images fall back to near-lossless), PSNR >= 32 dB (noise
# images land near 37 dB at q 90: this only catches a broken quantizer). Prints size vs lossless.
# Run from yaif-lisaac/: test/lossy.sh [images...]
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY="uv run -q --with pillow python test/oracle.py"
fail=0
[ $# -eq 0 ] && set -- test/corpus/*
for f in "$@"; do
  n=$(basename "$f")
  ./test/img_probe "$f" "$T/$n.rgba" > /dev/null
  ./yaif encode "$f" "$T/ll.yaif" -m lossless > /dev/null
  ll=$(stat -c %s "$T/ll.yaif")
  for e in 1 2 4; do
    ./yaif encode "$f" "$T/$e.yaif" -m lossy -l 3 -e $e > /dev/null
    ./yaif decode "$T/$e.yaif" "$T/$e.png" > /dev/null
    r=$($PY near "$T/$n.rgba" "$T/$e.png" $e) || { echo "LOSSY FAILED: $f eps $e: $r"; fail=1; }
    s=$(stat -c %s "$T/$e.yaif")
    printf "%-24s eps %d  %9d bytes  %3d%% of lossless  %s\n" "$n" $e $s $((s * 100 / ll)) "$r"
  done
  YAIF_RECON="$T/r.png" ./yaif encode "$f" "$T/w.yaif" -m lossy -l 5 > /dev/null
  ./yaif decode "$T/w.yaif" "$T/w.png" > /dev/null
  uv run -q --with pillow python -c "import sys; from PIL import Image; a, b = (Image.open(x).convert('RGBA').tobytes() for x in sys.argv[1:]); sys.exit(a != b)" "$T/r.png" "$T/w.png" \
    || { echo "LOSSY FAILED: $f level 5: decoder differs from encoder reconstruction"; fail=1; }
  # q 50: the chroma filter at full strength, in the reconstruction too
  YAIF_RECON="$T/r50.png" ./yaif encode "$f" "$T/w50.yaif" -m lossy -l 5 -q 50 > /dev/null
  ./yaif decode "$T/w50.yaif" "$T/w50.png" > /dev/null
  uv run -q --with pillow python -c "import sys; from PIL import Image; a, b = (Image.open(x).convert('RGBA').tobytes() for x in sys.argv[1:]); sys.exit(a != b)" "$T/r50.png" "$T/w50.png" \
    || { echo "LOSSY FAILED: $f level 5 q 50: decoder differs from encoder reconstruction"; fail=1; }
  r=$($PY near "$T/$n.rgba" "$T/w.png" 255) || { echo "LOSSY FAILED: $f level 5: $r"; fail=1; }
  p=$(echo "$r" | sed 's/.*psnr=//')
  [ "${p%.*}" -ge 32 ] || { echo "LOSSY FAILED: $f level 5 psnr $p"; fail=1; }
  s=$(stat -c %s "$T/w.yaif")
  printf "%-24s q 90   %9d bytes  %3d%% of lossless  %s\n" "$n" $s $((s * 100 / ll)) "$r"
done
exit $fail
