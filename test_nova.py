#!/usr/bin/env python3.14
import os, tempfile
from PIL import Image
from nova import encode, decode

def tmp(ext='.nova'):
    return tempfile.mktemp(suffix=ext)

def cleanup(*paths):
    for p in paths:
        try: os.remove(p)
        except: pass

def test_roundtrip_static():
    img = Image.new('RGBA', (128, 128), (200, 100, 50, 180))
    # gradient
    px = img.load()
    for y in range(128):
        for x in range(128):
            px[x, y] = (x * 2, y * 2, 50, 200)

    path = tmp()
    encode(img, path)
    frames = decode(path)
    assert len(frames) == 1
    assert frames[0].size == (128, 128)
    p = frames[0].getpixel((64, 64))
    assert p[3] > 0, "alpha channel lost"
    cleanup(path)
    print("PASS  roundtrip_static")

def test_lossless_exact():
    img = Image.new('RGBA', (64, 64), (10, 20, 30, 255))
    path = tmp()
    encode(img, path, mode='lossless')
    frames = decode(path)
    assert frames[0].getpixel((0, 0)) == (10, 20, 30, 255), "lossless not exact"
    cleanup(path)
    print("PASS  lossless_exact")

def test_lossy_smaller():
    # Random noise image — lossy JPEG should be much smaller than lossless zlib
    import random
    rng = random.Random(42)
    img = Image.new('RGBA', (256, 256))
    px = img.load()
    for y in range(256):
        for x in range(256):
            px[x, y] = (rng.randint(0,255), rng.randint(0,255), rng.randint(0,255), 255)

    pl, pj = tmp(), tmp()
    encode(img, pl, mode='lossless')
    encode(img, pj, mode='lossy')
    sl, sj = os.path.getsize(pl), os.path.getsize(pj)
    assert sj < sl, f"lossy ({sj}) not smaller than lossless ({sl})"
    cleanup(pl, pj)
    print(f"PASS  lossy_smaller  lossless={sl}B lossy={sj}B")

def test_animation():
    frames_in = [Image.new('RGBA', (64, 64), (i * 50 % 256, 100, 200, 255))
                 for i in range(4)]
    path = tmp()
    encode(frames_in[0], path, frames=frames_in, frame_duration=50)
    frames_out = decode(path)
    assert len(frames_out) == 4, f"expected 4 frames, got {len(frames_out)}"
    cleanup(path)
    print("PASS  animation")

def test_metadata():
    img = Image.new('RGBA', (32, 32), (255, 0, 0, 255))
    fake_icc = b'fake-icc-profile-data'
    fake_exif = b'fake-exif-data'
    path = tmp()
    encode(img, path, icc_profile=fake_icc, exif=fake_exif)
    # verify info doesn't crash and file is valid
    frames = decode(path)
    assert len(frames) == 1
    cleanup(path)
    print("PASS  metadata")

def test_adaptive_mode():
    # Solid color block → lossy; high-frequency block → lossless
    img = Image.new('RGBA', (128, 128))
    px = img.load()
    for y in range(128):
        for x in range(128):
            # checkerboard = high variance → lossless
            px[x, y] = (255 if (x+y) % 2 == 0 else 0, 0, 0, 255)
    path = tmp()
    encode(img, path, mode='adaptive')
    frames = decode(path)
    assert frames[0].size == (128, 128)
    cleanup(path)
    print("PASS  adaptive_mode")

def test_express_preview():
    img = Image.new('RGB', (200, 100), (80, 160, 200))
    path = tmp()
    encode(img, path, mode='express', quality=60)
    # decode_preview returns the embedded thumbnail
    from nova import decode_preview
    prev = decode_preview(path)
    assert prev is not None, "no PREV chunk found"
    assert prev.width == 20 and prev.height == 10, f"unexpected thumbnail size {prev.size}"
    # full decode still works
    frames = decode(path)
    assert frames[0].size == (200, 100)
    cleanup(path)
    print("PASS  express_preview")

if __name__ == '__main__':
    test_roundtrip_static()
    test_lossless_exact()
    test_lossy_smaller()
    test_animation()
    test_metadata()
    test_adaptive_mode()
    test_express_preview()
    print("\nAll tests passed.")
