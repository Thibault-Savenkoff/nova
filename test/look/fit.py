import glob, numpy as np, sys
from PIL import Image
S = sys.argv[1]
def ppm(f):
    d = open(f, 'rb').read().split(b'\n', 3); w, h = map(int, d[1].split())
    return np.frombuffer(d[3], '>u2').reshape(h, w, 3).astype(np.float32) / 65535
def small(a, w=300, h=200):  # box average
    H, W = a.shape[:2]; a = a[:H // h * h, :W // w * w]
    return a.reshape(h, H // h, w, W // w, 3).mean((1, 3))
pairs = []
for f in sorted(glob.glob(S + '/IMG_*.ppm')):
    lin = ppm(f); jp = np.asarray(Image.open(f[:-4] + '.jpg')).astype(np.float32) / 255
    js = small(jp)
    best = None
    for dy in range(0, 11):          # alignment of the 3000x2000 crop in the 3012x2010 half-size frame
        for dx in range(0, 13):
            ls = small(lin[dy:dy + 2000, dx:dx + 3000])
            g = np.corrcoef(np.log(ls.mean(2) + 1e-4).ravel(), js.mean(2).ravel())[0, 1]
            if best is None or g > best[0]: best = (g, dy, dx, ls)
    print(f.split('/')[-1], 'align', best[1], best[2], 'corr %.3f' % best[0])
    pairs.append((best[3], js))
np.save(S + '/pairs.npy', np.array([(l, j) for l, j in pairs]))
