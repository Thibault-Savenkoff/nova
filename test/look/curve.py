import numpy as np, sys
P = np.load(sys.argv[1] + '/pairs.npy')          # n, 2, 200, 300, 3
L, J = P[:, 0], P[:, 1]
def srgb(x): x = np.clip(x, 0, 1); return np.where(x <= 0.0031308, 12.92 * x, 1.055 * x ** (1 / 2.4) - 0.055)
def err(out): return np.abs(out - J).mean(axis=(1, 2, 3)) * 255
# Before: LibRaw auto-bright (white = 99th percentile of the frame) + sRGB curve.
before = np.stack([srgb(l / np.percentile(l, 99)) for l in L])
print('before  mean %.1f  per file' % err(before).mean(), np.round(err(before), 1))
# Tone curve shared by the 3 channels, as a table over log2(linear), fitted on all files but one (check).
edges = np.linspace(-14, 0.5, 59)
def fit(idx):
    x = np.log2(np.maximum(L[idx], 2 ** -14)).ravel(); y = J[idx].ravel()
    b = np.digitize(x, edges); c = np.array([np.median(y[b == i]) if (b == i).sum() > 50 else np.nan for i in range(1, len(edges))])
    xs = (edges[1:] + edges[:-1]) / 2; ok = ~np.isnan(c)
    c = np.maximum.accumulate(np.interp(xs, xs[ok], c[ok]))   # monotone
    return xs, c
def apply(l, xs, c): return np.interp(np.log2(np.maximum(l, 2 ** -14)), xs, c)
xs, c = fit(range(len(L)))
curve = np.stack([apply(l, xs, c) for l in L])
print('curve   mean %.1f  per file' % err(curve).mean(), np.round(err(curve), 1))
# Leave-one-out: does the curve hold on a file it did not see?
loo = [np.abs(apply(L[i], *fit([j for j in range(len(L)) if j != i])) - J[i]).mean() * 255 for i in range(len(L))]
print('held-out mean %.1f' % np.mean(loo))
# Saturation around the per-pixel mean.
for s in (1.0, 1.1, 1.2, 1.3, 1.4):
    m = curve.mean(-1, keepdims=True); o = np.clip(m + s * (curve - m), 0, 1)
    print('sat %.1f  mean %.2f' % (s, err(o).mean()))
np.save(sys.argv[1] + '/curve.npy', np.stack([xs, c]))
for x, y in zip(xs[::3], c[::3]): print('  log2 %.2f -> %.3f' % (x, y))
