#!/bin/bash
# Unit tests of libyaifdec (test/libyaif_unit.c): inflate against zlib, bad input, yaif_icc on
# a JPEG (70 KB profile over 2 APP2 segments), a PNG (iCCP) and a file without a profile.
# Needs zlib-devel and Pillow (uv). Run from the repo: test/libyaif_unit.sh
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gcc -std=c99 -O2 -Wall -Wextra -Werror -o "$T/unit" test/libyaif_unit.c -lz
# Sanitizers when they are installed (libasan; libubsan is replaced by trapping, which needs no library).
SAN=
gcc -std=c99 -O1 -g -fsanitize=address -fsanitize=undefined -fsanitize-trap=all -fno-sanitize=alignment \
    -w -o "$T/unit_san" test/libyaif_unit.c -lz 2> /dev/null && SAN="$T/unit_san"
uv run -q --with pillow python - "$T" <<'EOF'
import os, sys
from PIL import Image
t = sys.argv[1]
im = Image.new("RGB", (40, 30), (10, 200, 30))
icc = os.urandom(70000)
open(f"{t}/a.icc", "wb").write(icc)
open(f"{t}/b.icc", "wb").write(icc[:3000])
im.save(f"{t}/a.jpg", icc_profile=icc)
im.save(f"{t}/b.png", icc_profile=icc[:3000])
im.save(f"{t}/c.png")
EOF
for f in a.jpg b.png c.png; do ./yaif encode "$T/$f" "$T/${f%.*}.yaif" > /dev/null; done
# The site samples too (animation, PREV thumbnail, gain map, lossy), with no expected profile.
SAMPLES=$(for f in docs/samples/*.yaif; do printf '%s ? ' "$f"; done)
# valgrind on the plain build (it and ASan cannot run together), ASan on its own build.
V=
command -v valgrind > /dev/null && V="valgrind -q --error-exitcode=1"
[ -n "$SAN" ] && { echo "with AddressSanitizer:"; "$SAN" "$T/a.yaif" "$T/a.icc" "$T/b.yaif" "$T/b.icc" "$T/c.yaif" - $SAMPLES || exit 1; }
$V "$T/unit" "$T/a.yaif" "$T/a.icc" "$T/b.yaif" "$T/b.icc" "$T/c.yaif" - $SAMPLES
