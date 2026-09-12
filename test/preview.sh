#!/bin/bash
# PREV thumbnail: large opaque and alpha images get a 512 px preview close to a box-filtered
# thumbnail (mean error <= 6: codec loss + filter rounding differences with PIL); a small image
# has none and `nova preview` falls back to the full frame.
# Run from nova-lisaac/: test/preview.sh
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export UV_OFFLINE=1
uv run -q --with pillow --with numpy python - "$T" <<'EOF'
import sys, numpy as np
from PIL import Image
t = sys.argv[1]
y, x = np.mgrid[0:1500, 0:2000]
rgb = np.stack([x % 256, y % 256, (x + y) % 256], 2).astype(np.uint8)
Image.fromarray(rgb).save(f"{t}/opaque.png")
a = (x * 255 // 1999).astype(np.uint8)[..., None]
Image.fromarray(np.concatenate([rgb, a], 2)).save(f"{t}/alpha.png")
EOF
fail=0
for f in opaque alpha; do
  ./nova encode "$T/$f.png" "$T/$f.nova" > /dev/null
  ./nova preview "$T/$f.nova" "$T/$f.prev.png" > /dev/null
  r=$(uv run -q --with pillow --with numpy python -c "
import sys, numpy as np; from PIL import Image
p = Image.open(sys.argv[2]).convert('RGBA'); o = Image.open(sys.argv[1]).convert('RGBA').resize(p.size, Image.BOX)
d = np.abs(np.asarray(p, int) - np.asarray(o, int))
print(p.size, 'alpha_err', d[..., 3].max(), 'mean_err', round(d[..., :3].mean(), 2))
sys.exit(int(p.size != (512, 384) or d[..., 3].max() > 3 or d[..., :3].mean() > 6))" "$T/$f.png" "$T/$f.prev.png")
  [ $? -eq 0 ] && echo "OK   $f $r" || { echo "FAIL $f $r"; fail=1; }
done
./nova encode test/corpus/alpha.png "$T/s.nova" > /dev/null
./nova preview "$T/s.nova" "$T/s.png" > /dev/null
./nova decode "$T/s.nova" "$T/d.png" > /dev/null
cmp -s "$T/s.png" "$T/d.png" && echo "OK   small image: preview = full frame" || { echo "FAIL small image preview"; fail=1; }
exit $fail
