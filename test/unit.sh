#!/bin/bash
# Unit tests of the Lisaac modules (test/unit.li), with child processes and without
# (NOVA_THREADS=1), then `nova decode` on corrupt copies of real files: it must end with an
# error or a picture, never crash (signal) or hang. Run from the repo: test/unit.sh
cd "$(dirname "$0")" || exit 1
lisaac unit.li -add_path "$PWD/.." -boost > /dev/null 2>&1 || exit 1
cd .. || exit 1
fail=0
NOVA=${NOVA:-./nova}   # e.g. a build with sanitizers
./test/unit || fail=1
NOVA_THREADS=1 ./test/unit | tail -1 || fail=1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# Sources of the corrupt files: the site samples and every level, alpha and near-lossless.
C=test/corpus
enc() { $NOVA encode "$C/$1" "$T/src_$2.nova" "${@:3}" > /dev/null 2>&1 || { echo "FAIL encode $*"; fail=1; }; }
enc text.png l0 -m lossless -l 0
for l in 1 2 3 4; do enc gradient.png l$l -m lossless -l $l; done
enc alpha.png alpha3 -m lossless -l 3
enc alpha.png alpha5 -m lossy
enc photo_like.jpg l5 -m lossy -q 70
enc photo_like.jpg eps -m lossy -l 2 -e 3
UV_OFFLINE=1 uv run -q python - "$T" docs/samples/*.nova "$T"/src_*.nova <<'EOF'
import random, struct, sys, zlib
t, files = sys.argv[1], sys.argv[2:]

def fix_crcs(b):
    # Every CRC made right again after the corruption, so the damage reaches the decoders.
    p = 9
    while p + 8 <= len(b):
        n = struct.unpack(">I", b[p + 4:p + 8])[0]
        if p + 12 + n > len(b): break
        b[p + 8 + n:p + 12 + n] = struct.pack(">I", zlib.crc32(b[p:p + 4] + b[p + 8:p + 8 + n]))
        p += 12 + n
    return b

r = random.Random(1)
for f in files:
    d = open(f, "rb").read()
    for i in range(60):
        b = bytearray(d)
        k = i % 4
        if k == 0:                      # a few flipped bytes anywhere
            for _ in range(r.randint(1, 4)): b[r.randrange(len(b))] = r.randrange(256)
        elif k == 1:                    # cut short
            b = b[:r.randrange(len(b))]
        elif k == 2:                    # one byte flipped in the first 200 (header, chunk lengths)
            b[r.randrange(min(200, len(b)))] ^= 1 << r.randrange(8)
        else:                           # random tail
            p = r.randrange(len(b))
            b[p:] = bytes(r.randrange(256) for _ in range(len(b) - p))
        if i % 8 < 4: b = fix_crcs(b)
        open(f"{t}/x_{f.split('/')[-1][:-5]}_{i}.nova", "wb").write(b)
EOF
n=0
for f in "$T"/x_*.nova; do
  timeout 60 $NOVA decode "$f" "$T/out.png" > /dev/null 2>&1
  c=$?
  if [ $c -ge 124 ]; then echo "FAIL nova decode $(basename "$f"): exit $c (crash or hang)"; fail=1; cp "$f" /tmp/; fi
  n=$((n + 1))
done
echo "nova decode on $n corrupt files"
exit $fail
