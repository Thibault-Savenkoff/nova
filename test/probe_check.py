# Compare img_probe's raw RGBA dump with PIL's decode. Usage: probe_check.py img dump
import sys
from PIL import Image
ref = Image.open(sys.argv[1]).convert("RGBA").tobytes()
got = open(sys.argv[2], "rb").read()
if len(ref) != len(got):
    sys.exit(f"FAIL size {len(got)} != {len(ref)}")
diff = max(abs(a - b) for a, b in zip(ref, got))
print(f"{'OK  ' if diff == 0 else 'DIFF'} max_err={diff} {sys.argv[1]}")
