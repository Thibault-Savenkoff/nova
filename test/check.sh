#!/bin/bash
# Round trip every corpus image through yaif (exact pixels) and print a size table.
# Run from yaif-lisaac/: test/check.sh [images...]
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY="uv run -q --with pillow python test/oracle.py"
[ -x test/img_probe ] || (cd test && lisaac img_probe.li > /dev/null)
fail=0
# Destination left out: derived from the source, next to it (no terminal here, so no question).
cp test/corpus/* "$T/" 2>/dev/null || true
d=$(ls "$T" | head -1)
./yaif encode "$T/$d" > /dev/null
[ -f "$T/${d%.*}.yaif" ] || { echo "DERIVED DESTINATION FAILED: $T/${d%.*}.yaif"; fail=1; }
# A last name that is not a readable file stays the destination, .yaif or not.
./yaif encode "$T/$d" "$T/out.img" > /dev/null
[ -f "$T/out.img" ] || { echo "EXPLICIT DESTINATION FAILED"; fail=1; }
printf "%-28s %9s %9s %9s %8s %8s\n" image yaif png_opt webp_ll yaif/png yaif/webp
[ $# -eq 0 ] && set -- test/corpus/*
for f in "$@"; do
  n=$(basename "$f")
  ./yaif encode "$f" "$T/$n.yaif" -m lossless > /dev/null
  ./yaif decode "$T/$n.yaif" "$T/$n.png" > /dev/null
  # Reference = what lib/draw/img decoded from the source (JPEG decoders differ from PIL).
  ./test/img_probe "$f" "$T/$n.rgba" > /dev/null
  $PY same "$T/$n.rgba" "$T/$n.png" > /dev/null || { echo "ROUND TRIP FAILED: $f"; fail=1; }
  # PNG/WebP reference sizes are slow (minutes per photo): cached by path + source size.
  key="$f $(stat -c %s "$f")"
  ref=$(grep -F "$key " test/.ref_sizes 2>/dev/null | tail -1 | awk '{print $(NF-1), $NF}')
  if [ -z "$ref" ]; then
    ref=$($PY sizes "$f")
    echo "$key $ref" >> test/.ref_sizes
  fi
  read png webp <<< "$ref"
  yaif=$(stat -c %s "$T/$n.yaif")
  printf "%-28s %9d %9d %9d %7d%% %7d%%\n" "$n" "$yaif" "$png" "$webp" $((yaif * 100 / png)) $((yaif * 100 / webp))
done
exit $fail
