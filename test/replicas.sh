#!/bin/bash
# Multi-core wasm (docs/yaif_enc.js run as replicas, test/replicas.js): encoding in each mode and
# decoding must give the same bytes as native yaif. Files: $@ (default: the corpus, a 2800x2000
# photo crop: several stripes, one CR3). N=replica count (default 3: uneven job split).
cd "$(dirname "$0")/.." || exit 1
export LC_ALL=C UV_OFFLINE=1
N=${N:-3}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
if [ $# -eq 0 ]; then
  ./yaif encode ~/photos-yaif/IMG_0577.HEIC $T/h.yaif -m lossless -l 1 >/dev/null 2>&1 && ./yaif decode $T/h.yaif $T/h.png >/dev/null 2>&1
  uv run -q --with pillow python -c "
from PIL import Image
Image.open('$T/h.png').convert('RGB').crop((0, 0, 2800, 2000)).save('$T/photo.png')"
  set -- test/corpus/* $T/photo.png "$(ls ~/photos-yaif/cr3/*.CR3 | head -1)"
fi
fail=0
same() {  # $1 label, then the yaif arguments with OUT for the output file
  local label=$1; shift
  local args=("$@") nat=() was=()
  for a in "${args[@]}"; do nat+=("${a/OUT/$T/n}"); was+=("${a/OUT/$T/w}"); done
  ./yaif "${nat[@]}" >/dev/null 2>&1 || { echo "FAIL $label: native"; fail=1; return; }
  node test/replicas.js $N "${was[@]:1:2}" "${was[@]:3}" 2>$T/err >/dev/null || { echo "FAIL $label: $(tail -1 $T/err)"; fail=1; return; }
  cmp -s "${nat[2]}" "${was[2]}" && echo "ok   $label" || { echo "FAIL $label: output differs"; fail=1; }
}
for f in "$@"; do
  b=$(basename "$f")
  for m in adaptive lossless lossy "lossy -q 50"; do
    case $f in *.CR3) [ "$m" = adaptive ] || continue;; esac
    same "$b -m $m" encode "$f" OUT.yaif -m $m
    cp $T/n.yaif $T/src.yaif
    same "$b -m $m decode" decode $T/src.yaif OUT.jpg
  done
done
[ $fail = 0 ] && echo "all same ($N replicas)"
exit $fail
