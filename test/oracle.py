# Oracle for nova-lisaac.
#   oracle.py same <ref.rgba> <decoded.png> <w> <h>  -> exact pixel compare (decoded read by PIL)
#   oracle.py sizes <src>                             -> sizes of best-effort PNG / WebP lossless
#   oracle.py near <ref.rgba> <decoded.png> <eps>     -> lossy: |error| <= eps on RGB, alpha exact; prints PSNR
#                                                        (eps 255: RGB of alpha-0 pixels ignored)
import io, sys
from PIL import Image

if sys.argv[1] == "same":
    ref = open(sys.argv[2], "rb").read()
    got = Image.open(sys.argv[3]).convert("RGBA").tobytes()
    if ref != got:
        n = sum(a != b for a, b in zip(ref, got))
        sys.exit(f"FAIL {sys.argv[3]}: {n} bytes differ (len {len(got)} vs {len(ref)})")
    print(f"OK   {sys.argv[3]}")
elif sys.argv[1] == "near":
    import math
    ref = open(sys.argv[2], "rb").read()
    got = Image.open(sys.argv[3]).convert("RGBA").tobytes()
    eps = int(sys.argv[4])
    d = [abs(a - b) for a, b in zip(ref, got)]
    alpha = max(d[3::4])
    # eps 255 = level 5: the RGB of fully transparent pixels is replaced on purpose, not checked.
    rgbi = [i for i in range(len(d)) if i % 4 != 3 and (eps < 255 or ref[i | 3] > 0)] or [0]
    rgb = max(d[i] for i in rgbi)
    mse = sum(d[i] ** 2 for i in rgbi) / len(rgbi)
    psnr = 99.0 if mse == 0 else 10 * math.log10(255 * 255 / mse)
    ok = len(ref) == len(got) and rgb <= eps and alpha == 0
    print(f"{'OK  ' if ok else 'FAIL'} max_err={rgb} alpha_err={alpha} psnr={psnr:.1f}")
    sys.exit(0 if ok else 1)
else:
    im = Image.open(sys.argv[2])
    im = im.convert("RGBA" if "A" in im.getbands() else "RGB")
    out = []
    for fmt, kw in (("PNG", {"optimize": True}), ("WEBP", {"lossless": True, "quality": 100, "method": 6})):
        b = io.BytesIO()
        im.save(b, fmt, **kw)
        out.append(str(len(b.getvalue())))
    print(" ".join(out))
