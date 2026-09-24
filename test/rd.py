# Rate-distortion comparison of YAIF level 5 against WebP and AVIF, at equal quality.
#   uv run --with pillow --with numpy python test/rd.py <image> [yaif qualities...]
# For each codec: bytes, PSNR (RGB) and SSIM (luma) over a quality sweep, then the size each codec
# needs at fixed PSNR targets (log-size interpolated): YAIF/WebP < 100 % means YAIF is smaller.
import io, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image

src = sys.argv[1]
yaif_q = [int(q) for q in sys.argv[2:]] or [30, 45, 60, 75, 90]
ref_im = Image.open(src).convert("RGB")
ref = np.asarray(ref_im, float)


def psnr(b):
    m = ((ref - b) ** 2).mean()
    return 99.0 if m == 0 else 10 * np.log10(255 * 255 / m)


def box(x, r=4):
    # mean over (2r+1)^2 windows, valid part only
    c = np.cumsum(np.cumsum(np.pad(x, ((1, 0), (1, 0))), 0), 1)
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def ssim(b):
    y = lambda a: a @ [0.299, 0.587, 0.114]
    x1, x2 = y(ref), y(b)
    m1, m2 = box(x1), box(x2)
    v1, v2, cv = box(x1 * x1) - m1 ** 2, box(x2 * x2) - m2 ** 2, box(x1 * x2) - m1 * m2
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    return float((((2 * m1 * m2 + c1) * (2 * cv + c2)) / ((m1 ** 2 + m2 ** 2 + c1) * (v1 + v2 + c2))).mean())


def pil_codec(fmt, q, **kw):
    b = io.BytesIO()
    ref_im.save(b, fmt, quality=q, **kw)
    return len(b.getvalue()), np.asarray(Image.open(io.BytesIO(b.getvalue())).convert("RGB"), float)


def yaif(q):
    with tempfile.TemporaryDirectory() as t:
        subprocess.run(["./yaif", "encode", src, f"{t}/a.yaif", "-m", "lossy", "-l", "5", "-q", str(q)], check=True, capture_output=True)
        subprocess.run(["./yaif", "decode", f"{t}/a.yaif", f"{t}/a.png"], check=True, capture_output=True)
        return os.path.getsize(f"{t}/a.yaif"), np.asarray(Image.open(f"{t}/a.png").convert("RGB"), float)


import json
cache_file = "test/.rd_cache.json"
cache = json.load(open(cache_file)) if os.path.exists(cache_file) else {}
key = f"{src} {os.path.getsize(src)}"
quiet = os.environ.get("RD_QUIET")
def heic(q):
    with tempfile.TemporaryDirectory() as t:
        subprocess.run(["heif-enc", "-q", str(q), src, "-o", f"{t}/a.heic"], check=True, capture_output=True)
        subprocess.run(["heif-dec", f"{t}/a.heic", f"{t}/a.png"], check=True, capture_output=True)
        return os.path.getsize(f"{t}/a.heic"), np.asarray(Image.open(f"{t}/a.png").convert("RGB"), float)


curves = {}
runs = {
    "yaif": [(q, lambda q=q: yaif(q)) for q in yaif_q],
    "webp": [(q, lambda q=q: pil_codec("WEBP", q, method=6)) for q in (30, 50, 70, 80, 90, 95, 98)],
    "avif": [(q, lambda q=q: pil_codec("AVIF", q, speed=4)) for q in (30, 50, 70, 80, 90, 95)],
    "heic": [(q, lambda q=q: heic(q)) for q in (30, 50, 70, 80, 90, 95)],
}
npx = ref.shape[0] * ref.shape[1]
for name, pts in runs.items():
    if name != "yaif" and name + " " + key in cache:
        curves[name] = cache[name + " " + key]
        continue
    curves[name] = []
    for q, f in pts:
        size, dec = f()
        p, s = psnr(dec), ssim(dec)
        curves[name].append((size, p, s))
        if not quiet: print(f"{name:5s} q{q:3d} {size:9d} B {size * 8 / npx:6.3f} bpp  psnr {p:5.2f}  ssim {s:.4f}")
    if name != "yaif":
        cache[name + " " + key] = curves[name]
        json.dump(cache, open(cache_file, "w"))


def size_at(name, target, k):
    pts = sorted(curves[name], key=lambda c: c[k])
    for (s0, *m0), (s1, *m1) in zip(pts, pts[1:]):
        a, b = m0[k - 1], m1[k - 1]
        if a <= target <= b and b > a:
            t = (target - a) / (b - a)
            return np.exp(np.log(s0) + t * (np.log(s1) - np.log(s0)))
    return None


print()
for k, label, targets in ((1, "psnr", (34, 36, 38, 40, 42, 44, 46, 48)), (2, "ssim", (0.95, 0.97, 0.98, 0.99))):
    for tg in targets:
        n, w, a, hc = (size_at(c, tg, k) for c in ("yaif", "webp", "avif", "heic"))
        fmt = lambda v: f"{v:9.0f}" if v else "        -"
        rel = lambda x: f"{100 * n / x:5.0f}%" if n and x else "     -"
        print(f"{label} {tg:<5}  yaif {fmt(n)}  webp {fmt(w)}  avif {fmt(a)}   yaif/webp {rel(w)}  yaif/avif {rel(a)}  yaif/heic {rel(hc)}")
