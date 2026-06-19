#!/usr/bin/env python3
"""Generate NOVA Viewer icon assets (PNG, ICO, ICNS, DMG background)."""

import os, platform, shutil, subprocess
from PIL import Image, ImageDraw, ImageFilter


def _render_raw(size: int) -> Image.Image:
    """Render at `size` with no anti-aliasing — call via render() for smooth output."""

    # ── rounded-rect mask ────────────────────────────────────────────────────
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size - 1, size - 1)], radius=size // 5, fill=255)

    # ── background ───────────────────────────────────────────────────────────
    bg = Image.new("RGBA", (size, size), (12, 18, 30, 255))

    # ── blue glow (clipped to rounded rect) ──────────────────────────────────
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [(-size // 3, -size // 3), (size // 2, size // 2)],
        fill=(50, 120, 255, 45))
    glow_clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_clipped.paste(glow, mask=mask)
    base = Image.alpha_composite(bg, glow_clipped)

    # ── geometric "N" ────────────────────────────────────────────────────────
    d   = ImageDraw.Draw(base)
    m   = int(size * 0.22)          # margin > corner radius so N is clearly inside
    bar = int(size * 0.12)          # stroke width
    t, b = m, size - m             # top / bottom y
    l, r = m, size - m             # left / right x
    c = (228, 236, 255)

    d.rectangle([l,         t, l + bar,     b], fill=c)   # left vertical
    d.rectangle([r - bar,   t, r,           b], fill=c)   # right vertical
    d.polygon([                                             # diagonal
        (l + bar,     t),
        (l + bar * 2, t),
        (r,           b),
        (r - bar,     b),
    ], fill=c)

    # ── blue accent dot — bottom-right corner, outside the N strokes ──────────
    dot = int(size * 0.07)
    # sits just to the right of the right bar bottom, in the free corner space
    dx  = r + int(size * 0.02)
    dy  = b - dot
    d.ellipse([dx, dy, dx + dot, dy + dot], fill=(74, 158, 255))

    # ── apply rounded-rect mask for final transparency ───────────────────────
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(base, mask=mask)
    return result


def render(size: int) -> Image.Image:
    """Render at 4× then downscale for smooth anti-aliased edges."""
    big = _render_raw(size * 4)
    return big.resize((size, size), Image.LANCZOS)


def make_png(path="assets/icon.png") -> str:
    os.makedirs("assets", exist_ok=True)
    render(1024).save(path)
    print(f"  {path}")
    return path


def make_ico(out="assets/nova_viewer.ico") -> str:
    sizes = [16, 32, 48, 64, 128, 256]
    imgs  = [render(s) for s in sizes]
    imgs[0].save(out, format="ICO", sizes=[(s, s) for s in sizes],
                 append_images=imgs[1:])
    print(f"  {out}")
    return out


def make_icns(out="assets/nova_viewer.icns") -> str:
    """macOS only — requires iconutil (ships with Xcode CLT)."""
    iconset = "assets/nova_viewer.iconset"
    os.makedirs(iconset, exist_ok=True)
    for s in [16, 32, 64, 128, 256, 512, 1024]:
        render(s).save(f"{iconset}/icon_{s}x{s}.png")
        if s <= 512:
            render(s * 2).save(f"{iconset}/icon_{s}x{s}@2x.png")
    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", out])
    shutil.rmtree(iconset)
    print(f"  {out}")
    return out


def make_dmg_bg(path="assets/dmg_bg.png") -> str:
    """1320×800 background for the DMG window (displayed at 660×400 @2x)."""
    os.makedirs("assets", exist_ok=True)
    W, H = 1320, 800

    # Dark navy base
    img = Image.new("RGB", (W, H), (10, 15, 26))
    d = ImageDraw.Draw(img)

    # Subtle blue radial glow — top-left
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([-300, -300, 900, 900], fill=(30, 80, 200, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    d = ImageDraw.Draw(img)

    # Large faint "N" watermark in centre
    S = 420
    m = int(S * 0.18)
    bar = int(S * 0.13)
    cx, cy = W // 2, H // 2
    ox, oy = cx - S // 2, cy - S // 2
    t, b = oy + m, oy + S - m
    l, r = ox + m, ox + S - m
    c = (255, 255, 255, 18)
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rectangle([l,       t, l + bar,     b], fill=c)
    od.rectangle([r - bar, t, r,           b], fill=c)
    od.polygon([(l + bar, t), (l + bar * 2, t), (r, b), (r - bar, b)], fill=c)
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

    # Thin separator line at bottom (drag-here hint area)
    d = ImageDraw.Draw(img)
    d.line([(0, H - 2), (W, H - 2)], fill=(255, 255, 255, 15), width=2)

    img.save(path)
    print(f"  {path}")
    return path


if __name__ == "__main__":
    print("Generating icons…")
    make_png()
    make_ico()
    if platform.system() == "Darwin":
        make_icns()
        make_dmg_bg()
    print("Done.")
