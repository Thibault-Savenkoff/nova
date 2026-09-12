#!/bin/bash
# Lossy checks. Near-lossless (level 3): max error <= eps, alpha exact. Wavelet (level 5, q 90):
# the decoder rebuilds exactly the encoder's reconstruction (NOVA_RECON), alpha exact (alpha images
# fall back to near-lossless), PSNR >= 32 dB (noise images land near 37 dB at q 90: this only catches
# a broken quantizer). Prints size vs lossless.
# Run from nova-lisaac/: test/lossy.sh [images...]
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
  ./nova encode "$f" "$T/ll.nova" -m lossless > /dev/null
  ll=$(stat -c %s "$T/ll.nova")
  for e in 1 2 4; do
    ./nova encode "$f" "$T/$e.nova" -m lossy -l 3 -e $e > /dev/null
    ./nova decode "$T/$e.nova" "$T/$e.png" > /dev/null
    r=$($PY near "$T/$n.rgba" "$T/$e.png" $e) || { echo "LOSSY FAILED: $f eps $e: $r"; fail=1; }
    s=$(stat -c %s "$T/$e.nova")
    printf "%-24s eps %d  %9d bytes  %3d%% of lossless  %s\n" "$n" $e $s $((s * 100 / ll)) "$r"
  done
  NOVA_RECON="$T/r.png" ./nova encode "$f" "$T/w.nova" -m lossy -l 5 > /dev/null
  ./nova decode "$T/w.nova" "$T/w.png" > /dev/null
  uv run -q --with pillow python -c "import sys; from PIL import Image; a, b = (Image.open(x).convert('RGBA').tobytes() for x in sys.argv[1:]); sys.exit(a != b)" "$T/r.png" "$T/w.png" \
    || { echo "LOSSY FAILED: $f level 5: decoder differs from encoder reconstruction"; fail=1; }
  r=$($PY near "$T/$n.rgba" "$T/w.png" 255) || { echo "LOSSY FAILED: $f level 5: $r"; fail=1; }
  p=$(echo "$r" | sed 's/.*psnr=//')
  [ "${p%.*}" -ge 32 ] || { echo "LOSSY FAILED: $f level 5 psnr $p"; fail=1; }
  s=$(stat -c %s "$T/w.nova")
  printf "%-24s q 90   %9d bytes  %3d%% of lossless  %s\n" "$n" $s $((s * 100 / ll)) "$r"
done
exit $fail
