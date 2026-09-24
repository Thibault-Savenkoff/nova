# Generate the synthetic test corpus (PNG + one JPEG).
import random
from PIL import Image, ImageDraw
out = "corpus/"
w, h = 256, 192
img = Image.new("RGB", (w, h))
img.putdata([(x, y, (x + y) // 2) for y in range(h) for x in range(w)])
img.save(out + "gradient.png")
img = Image.new("RGB", (w, h))
img.putdata([((255, 255, 255) if (x // 8 + y // 8) % 2 else (20, 40, 200)) for y in range(h) for x in range(w)])
img.save(out + "checker.png")
img = Image.new("RGB", (w, h), (255, 255, 255))
d = ImageDraw.Draw(img)
for i in range(12):
    d.text((8, 4 + i * 15), "YAIF v2 lossless codec test line %d" % i, fill=(0, 0, 0))
img.save(out + "text.png")
rng = random.Random(42)
img = Image.new("RGB", (w, h))
img.putdata([(rng.randrange(256), rng.randrange(256), rng.randrange(256)) for _ in range(w * h)])
img.save(out + "noise.png")
img = Image.new("RGBA", (w, h))
img.putdata([(x, 128, 255 - x, (x * y) % 256) for y in range(h) for x in range(w)])
img.save(out + "alpha.png")
img = Image.new("RGB", (w, h))
img.putdata([(x, y, (x * y) % 256) for y in range(h) for x in range(w)])
img.save(out + "photo_like.jpg", quality=90)
