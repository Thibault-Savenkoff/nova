# NOVA Image Format

An open, patent-free binary image format combining the best of PNG, JPEG, WebP, GIF and HEIC.

**Features:** adaptive/lossless/lossy/express compression · alpha channel · HDR · animation · structured metadata · competitive size vs PNG/JPEG

---

## Requirements

- Python 3.11+
- Pillow (`pip install pillow`)

---

## Format spec

```
Magic  (8 bytes) : \x89NOVA\r\n\x1a\n
Chunks           : [4b type][4b length][data][4b CRC32]
```

| Chunk | Description |
|-------|-------------|
| `IHDR` | Width, height, bit depth, flags (alpha/HDR/animated), compression mode |
| `MDAT` | ICC profile + EXIF (length-prefixed) |
| `ANIM` | Frame count, duration (ms), loop count |
| `PREV` | Express mode: low-res JPEG thumbnail (~10% size) for instant preview |
| `FDAT` | Full frame data |
| `FDLT` | Animation delta frame: bounding box + compressed region |
| `IEND` | End marker |

### Compression modes

| Mode | Behaviour |
|------|-----------|
| `adaptive` | Tries lossless and lossy on the whole frame, keeps the smaller result |
| `lossless` | PNG-compressed (all 5 adaptive filters), pixel-perfect |
| `lossy` | JPEG whole frame — smallest for photos |
| `express` | JPEG + embedded thumbnail (`PREV` chunk) for instant preview on slow storage |

---

## Python API

```python
from nova import encode, decode, decode_preview

# Encode
encode("input.png", "output.nova")
encode("input.jpg", "output.nova", quality=75, mode="lossy")
encode("input.png", "output.nova", mode="express", quality=60)

# Encode animation
frames = [Image.open(f) for f in frame_files]
encode(frames[0], "anim.nova", frames=frames, frame_duration=50)

# Decode
images = decode("output.nova")          # list of PIL.Image
images[0].save("roundtrip.png")

# Express: get thumbnail instantly, full image separately
thumb = decode_preview("output.nova")   # PIL.Image or None
```

### `encode` parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `quality` | `85` | JPEG quality (1–100). For express, 50–70 is recommended. |
| `mode` | `'adaptive'` | `'adaptive'` / `'lossless'` / `'lossy'` / `'express'` |
| `is_hdr` | `False` | HDR mode (float32 pixels) |
| `icc_profile` | `None` | Raw ICC profile bytes |
| `exif` | `None` | Raw EXIF bytes |
| `frames` | `None` | List of `PIL.Image` for animation |
| `frame_duration` | `100` | Milliseconds per frame |
| `loop` | `0` | Loop count (0 = infinite) |

---

## CLI

```bash
# Encode
python nova.py encode input.png output.nova
python nova.py encode input.jpg output.nova 75 lossy

# Decode
python nova.py decode output.nova roundtrip.png

# File info
python nova.py info output.nova

# Benchmark all modes vs original
python nova.py bench input.jpg
```

---

## NOVA Viewer

A standalone desktop app to open, create and convert `.nova` files.

```bash
python nova_viewer.py
python nova_viewer.py image.nova   # open directly
```

**Features:**
- Open and display `.nova` files (static and animated)
- Import any image (PNG/JPEG/GIF/WebP…) and save as `.nova`
- Export `.nova` to PNG/JPEG/GIF/WebP
- Animation playback controls
- Express mode: shows embedded thumbnail instantly while full image loads in background

### Build standalone app (no Python required)

```bash
python build.py
```

| Platform | Output | File association |
|----------|--------|-----------------|
| macOS | `dist/NOVAViewer.app` | Drag to `/Applications` — `.nova` files auto-associate |
| Windows | `dist/NOVAViewer.exe` | Registers `.nova` on first launch (no admin required) |
| Linux | `dist/NOVAViewer` + `dist/install.sh` | `sudo dist/install.sh` |

### Auto-update

Edit `UPDATE_URL` in `updater.py` to point to a JSON endpoint:

```json
{
  "version": "1.1.0",
  "notes": "What changed",
  "download": {
    "darwin": "https://your-server/NOVAViewer-mac.zip",
    "win32":  "https://your-server/NOVAViewer.exe",
    "linux":  "https://your-server/NOVAViewer"
  }
}
```

---

## C accelerator (optional)

`nova_accel.c` provides a faster `frame_diff_bbox` for animation encoding. `nova.py` loads it automatically if compiled in the same directory.

```bash
gcc -O2 -shared -fPIC -o nova_accel.so nova_accel.c
```

Falls back to pure Python if the `.so` is absent — no action required.

---

## Run tests

```bash
python test_nova.py
```

---

## License

MIT — see [LICENSE](LICENSE).
