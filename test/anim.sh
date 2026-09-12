#!/bin/bash
# Animation round trip: 1-pixel delta, identical frame (empty delta), big rectangle, corner pixel.
# Run from nova-lisaac/: test/anim.sh
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
uv run -q --with pillow python - "$T" <<'EOF'
import random, sys
from PIL import Image
random.seed(1)
t = sys.argv[1]
im = Image.new("RGB", (64, 48))
im.putdata([(random.randrange(256), x * 4, y * 5) for y in range(48) for x in range(64)])
frames = [im.copy()]
im.putpixel((10, 7), (1, 2, 3)); frames.append(im.copy())      # 1x1 delta
frames.append(im.copy())                                       # empty delta
for y in range(5, 40):
    for x in range(3, 60):
        im.putpixel((x, y), (x, y, x ^ y))
frames.append(im.copy())                                       # big rectangle
im.putpixel((63, 47), (9, 9, 9)); frames.append(im.copy())     # 1x1 at the last pixel
for i, f in enumerate(frames):
    f.save(f"{t}/src_{i}.png")
EOF
./nova encode "$T"/src_{0..4}.png "$T/a.nova" -m lossless -d 50
./nova info "$T/a.nova"
./nova decode "$T/a.nova" "$T/out.png"
uv run -q --with pillow python - "$T" <<'EOF'
import sys
from PIL import Image
t = sys.argv[1]
for i in range(5):
    a = Image.open(f"{t}/src_{i}.png").convert("RGBA").tobytes()
    b = Image.open(f"{t}/out_{i:03d}.png").convert("RGBA").tobytes()
    print("OK  " if a == b else "FAIL", "frame", i)
    if a != b: sys.exit(1)
EOF
# Wavelet (level 5) animation: deltas coded over the reconstructed frames, so no drift (PSNR per frame).
./nova encode "$T"/src_{0..4}.png "$T/w.nova" -m lossy -l 5 -q 90 -d 50
./nova decode "$T/w.nova" "$T/w.png"
uv run -q --with pillow --with numpy python - "$T" <<'PYEOF'
import sys
import numpy as np
from PIL import Image
t = sys.argv[1]
for i in range(5):
    a = np.asarray(Image.open(f"{t}/src_{i}.png").convert("RGB"), float)
    b = np.asarray(Image.open(f"{t}/w_{i:03d}.png").convert("RGB"), float)
    p = 10 * np.log10(255 * 255 / max(((a - b) ** 2).mean(), 1e-9))
    print("OK  " if p >= 30 else "FAIL", "level 5 frame", i, f"psnr {p:.1f}")
    if p < 30: sys.exit(1)
PYEOF
