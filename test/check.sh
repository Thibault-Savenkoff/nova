#!/bin/bash
# Round trip every corpus image through nova (exact pixels) and print a size table.
# Run from nova-lisaac/: test/check.sh [images...]
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PY="uv run -q --with pillow python test/oracle.py"
[ -x test/img_probe ] || (cd test && lisaac img_probe.li > /dev/null)
fail=0
printf "%-28s %9s %9s %9s %8s %8s\n" image nova png_opt webp_ll nova/png nova/webp
[ $# -eq 0 ] && set -- test/corpus/*
for f in "$@"; do
  n=$(basename "$f")
  ./nova encode "$f" "$T/$n.nova" -m lossless > /dev/null
  ./nova decode "$T/$n.nova" "$T/$n.png" > /dev/null
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
  nova=$(stat -c %s "$T/$n.nova")
  printf "%-28s %9d %9d %9d %7d%% %7d%%\n" "$n" "$nova" "$png" "$webp" $((nova * 100 / png)) $((nova * 100 / webp))
done
exit $fail
