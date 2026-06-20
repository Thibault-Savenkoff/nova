#!/usr/bin/env python3
"""
NOVA image format — adaptive lossless/lossy, alpha, HDR, animation, metadata.
Spec: magic + length-prefixed CRC'd chunks (PNG-inspired).
"""
from __future__ import annotations

import zlib, struct, io, os, sys, ctypes
from PIL import Image

# C accelerator for hot loops (falls back to pure Python if .so absent)
_accel = None
try:
    _lib = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nova_accel.so'))
    _lib.frame_diff_bbox.restype  = None
    _lib.frame_diff_bbox.argtypes = [ctypes.c_char_p, ctypes.c_char_p,
                                      ctypes.c_int, ctypes.c_int, ctypes.c_int,
                                      ctypes.POINTER(ctypes.c_int)]
    _accel = _lib
except OSError:
    pass

MAGIC = b'\x89NOVA\r\n\x1a\n'

CHUNK_IHDR = b'IHDR'
CHUNK_MDAT = b'MDAT'
CHUNK_ANIM = b'ANIM'
CHUNK_RMAP = b'RMAP'
CHUNK_FDAT = b'FDAT'
CHUNK_FDLT = b'FDLT'
CHUNK_PREV = b'PREV'   # express mode: low-res JPEG thumbnail for instant preview
CHUNK_IEND = b'IEND'

MODE_ADAPTIVE = 0
MODE_LOSSLESS = 1
MODE_LOSSY    = 2
MODE_EXPRESS  = 3   # lossy + embedded thumbnail for progressive display over slow links
MODE_NAMES    = {'adaptive': MODE_ADAPTIVE, 'lossless': MODE_LOSSLESS,
                 'lossy': MODE_LOSSY, 'express': MODE_EXPRESS}


# ── chunk I/O ─────────────────────────────────────────────────────────────────

def _write_chunk(f, chunk_type: bytes, data: bytes) -> None:
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    f.write(chunk_type)
    f.write(struct.pack('>I', len(data)))
    f.write(data)
    f.write(struct.pack('>I', crc))


def _read_chunk(f):
    chunk_type = f.read(4)
    if not chunk_type or len(chunk_type) < 4:
        return None, None
    (length,) = struct.unpack('>I', f.read(4))
    data = f.read(length)
    (crc,) = struct.unpack('>I', f.read(4))
    if crc != (zlib.crc32(chunk_type + data) & 0xFFFFFFFF):
        raise ValueError(f"CRC mismatch in chunk {chunk_type}")
    return chunk_type, data


def _read_all_chunks(path: str):
    chunks = []
    with open(path, 'rb') as f:
        if f.read(len(MAGIC)) != MAGIC:
            raise ValueError("Not a NOVA file")
        while True:
            ct, data = _read_chunk(f)
            if ct is None:
                break
            chunks.append((ct, data))
    return chunks


# ── compression primitives ────────────────────────────────────────────────────

def _compress_ll(img: Image.Image) -> bytes:
    """Lossless: PNG via PIL. HDR (mode F/I) stored as raw float32 bytes + zlib."""
    if img.mode == 'F':
        raw = zlib.compress(img.tobytes(), 9)
        return b'H' + raw
    buf = io.BytesIO()
    img.save(buf, 'PNG', compress_level=9)
    return b'P' + buf.getvalue()


def _compress_jpeg(img: Image.Image, quality: int) -> bytes:
    has_alpha = img.mode == 'RGBA'
    buf = io.BytesIO()
    img.convert('RGB').save(buf, 'JPEG', quality=quality)
    if not has_alpha:
        return b'J' + buf.getvalue()
    # 'A' marker: JPEG for RGB + zlib-compressed alpha channel
    alpha_bytes = zlib.compress(img.getchannel('A').tobytes(), 6)
    jpeg = buf.getvalue()
    return b'A' + struct.pack('>I', len(jpeg)) + jpeg + alpha_bytes


def _compress_hdr16(arr) -> bytes:
    import numpy as np
    return b'N' + zlib.compress(arr.astype('<u2').tobytes(), 6)


def _decompress_block(data: bytes, size: tuple, ch: int, is_hdr: bool = False) -> Image.Image:
    mode = 'RGBA' if ch == 4 else 'RGB'
    marker, payload = data[0:1], data[1:]
    if marker == b'H':
        raw = zlib.decompress(payload)
        return Image.frombytes('F', size, raw)
    if marker == b'N':
        import numpy as np
        raw = zlib.decompress(payload)
        h_px, w_px = size[1], size[0]
        f32 = np.frombuffer(raw, dtype='<u2').reshape(h_px, w_px, 3).astype(np.float32) / 65535.0
        t = np.clip((f32*(2.51*f32+0.03))/(f32*(2.43*f32+0.59)+0.14), 0.0, 1.0)
        arr8 = (np.power(t, 1/2.2) * 255.0).clip(0, 255).astype(np.uint8)
        return Image.fromarray(arr8, mode='RGB')
    if marker == b'A':
        jpeg_len = struct.unpack('>I', payload[:4])[0]
        rgb = Image.open(io.BytesIO(payload[4:4 + jpeg_len])).convert('RGB')
        alpha_raw = zlib.decompress(payload[4 + jpeg_len:])
        alpha = Image.frombytes('L', rgb.size, alpha_raw)
        img = rgb.convert('RGBA')
        img.putalpha(alpha)
    else:
        img = Image.open(io.BytesIO(payload))
        if not is_hdr:
            img = img.convert(mode)
    assert img.size == size, f"block size mismatch: got {img.size}, expected {size}"
    return img


# ── frame encoding / decoding ─────────────────────────────────────────────────

def _encode_full_frame(f, frame: Image.Image, mode: int, quality: int) -> None:
    w, h = frame.size

    if mode == MODE_LOSSLESS:
        _write_chunk(f, CHUNK_FDAT, _compress_ll(frame))

    elif mode == MODE_LOSSY:
        # _compress_jpeg handles alpha preservation automatically (marker 'A' vs 'J')
        _write_chunk(f, CHUNK_FDAT, _compress_jpeg(frame, quality))

    elif mode == MODE_EXPRESS:
        # PREV: tiny JPEG thumbnail (~10% size) arrives in first KB → instant preview
        tw, th = max(1, w // 10), max(1, h // 10)
        thumb = frame.resize((tw, th), Image.LANCZOS)
        buf = io.BytesIO()
        thumb.convert("RGB").save(buf, "JPEG", quality=25)
        _write_chunk(f, CHUNK_PREV, buf.getvalue())
        # Full image at requested quality (caller should use 50-70 for express)
        _write_chunk(f, CHUNK_FDAT, _compress_jpeg(frame, quality))

    else:  # adaptive: whole-frame, pick smaller of lossless vs lossy
        # ponytail: frame-level pick avoids per-block JPEG header overhead (~600B/block)
        # upgrade to per-block if mixed-content images (text+photo) need it
        ll = _compress_ll(frame)
        jj = _compress_jpeg(frame, quality)
        _write_chunk(f, CHUNK_FDAT, ll if len(ll) <= len(jj) else jj)


def _decode_full_frame(fdat: bytes, rmap: bytes | None, w: int, h: int, mode: int, ch: int = 4, is_hdr: bool = False) -> Image.Image:
    return _decompress_block(fdat, (w, h), ch, is_hdr)


# ── public API ────────────────────────────────────────────────────────────────

def encode(
    source,
    output_path: str,
    quality: int = 85,
    mode: str = 'adaptive',
    is_hdr: bool = False,
    icc_profile: bytes | None = None,
    exif: bytes | None = None,
    frames=None,
    frame_duration: int = 100,
    loop: int = 0,
) -> None:
    """Encode image(s) to NOVA format.

    mode='adaptive'  tries lossless and lossy on the whole frame, keeps the smaller result.
                     Best default: photos → lossy wins; graphics/text → lossless wins.
    mode='lossless'  PNG-compressed, pixel-perfect. Larger than JPEG on photos.
    mode='lossy'     JPEG-compressed whole frame. Smallest for photos; not exact on decode.
    mode='express'   Lossy + embedded thumbnail (PREV chunk). The thumbnail (~10% size,
                     quality 25) arrives in the first KB so viewers can show a preview
                     instantly while the full image downloads. Use quality=50-70.
    """
    _hdr16_arr = None
    try:
        import numpy as np
        if isinstance(source, np.ndarray) and source.dtype == np.uint16 \
                and source.ndim == 3 and source.shape[2] == 3:
            _hdr16_arr = source
            source = Image.fromarray((source >> 8).astype(np.uint8))
    except ImportError:
        pass

    if isinstance(source, str):
        img = Image.open(source)
        icc_profile = icc_profile or img.info.get('icc_profile')
        exif = exif or img.info.get('exif')
        source = img

    all_frames = frames if frames else [source]
    first = all_frames[0]
    w, h = first.size
    is_animated = len(all_frames) > 1
    has_alpha = any(fr.mode in ('RGBA', 'LA', 'PA') for fr in all_frames)

    # Auto-detect HDR: PIL modes F (float32) or I (int32) or I;16
    hdr_modes = ('F', 'I', 'I;16', 'I;16B')
    if not is_hdr:
        is_hdr = any(fr.mode in hdr_modes for fr in all_frames)

    if _hdr16_arr is not None:
        is_hdr = True
        is_animated = False
        has_alpha = False

    flags = 0
    if has_alpha:   flags |= 1
    if is_hdr:      flags |= 2
    if is_animated: flags |= 4

    cmode = MODE_NAMES.get(mode, MODE_ADAPTIVE)

    with open(output_path, 'wb') as f:
        f.write(MAGIC)
        _write_chunk(f, CHUNK_IHDR,
            struct.pack('>IIBBBB', w, h, 16 if is_hdr else 8, 0, flags, cmode))

        if icc_profile or exif:
            icc = icc_profile or b''
            ex  = exif or b''
            _write_chunk(f, CHUNK_MDAT,
                struct.pack('>I', len(icc)) + icc + struct.pack('>I', len(ex)) + ex)

        if is_animated:
            _write_chunk(f, CHUNK_ANIM,
                struct.pack('>IHH', len(all_frames), frame_duration, loop & 0xFFFF))

        img_mode = 'RGBA' if has_alpha else 'RGB'
        ch = 4 if has_alpha else 3
        prev = None
        prev_raw = None
        for frame in all_frames:
            frame_c = frame if is_hdr else frame.convert(img_mode)

            if _hdr16_arr is not None:
                _write_chunk(f, CHUNK_FDAT, _compress_hdr16(_hdr16_arr))
                _hdr16_arr = None
            elif is_animated and prev is not None:
                frame_raw = frame_c.tobytes()
                if _accel is not None:
                    bbox = (ctypes.c_int * 4)()
                    _accel.frame_diff_bbox(prev_raw, frame_raw, w, h, ch, bbox)
                    x0, y0, x1, y1 = bbox[0], bbox[1], bbox[2], bbox[3]
                    has_diff = (x1 - x0) > 0
                else:
                    pw, fw = prev.load(), frame_c.load()
                    x0, y0, x1, y1 = w, h, -1, -1
                    for py in range(h):
                        for px in range(w):
                            if fw[px, py] != pw[px, py]:
                                if px < x0: x0 = px
                                if py < y0: y0 = py
                                if px + 1 > x1: x1 = px + 1
                                if py + 1 > y1: y1 = py + 1
                    has_diff = x1 > x0

                if not has_diff:
                    _write_chunk(f, CHUNK_FDLT, struct.pack('>IIII', 0, 0, 0, 0))
                else:
                    region = frame_c.crop((x0, y0, x1, y1))
                    _write_chunk(f, CHUNK_FDLT,
                        struct.pack('>IIII', x0, y0, x1 - x0, y1 - y0) + _compress_ll(region))
                prev_raw = frame_raw
            else:
                _encode_full_frame(f, frame_c, cmode, quality)
                prev_raw = frame_c.tobytes()

            prev = frame_c

        _write_chunk(f, CHUNK_IEND, b'')


def decode(input_path: str) -> list:
    chunks = _read_all_chunks(input_path)
    by_type: dict[bytes, list] = {}
    for ct, data in chunks:
        by_type.setdefault(ct, []).append(data)

    w, h, bit_depth, colorspace, flags, cmode = \
        struct.unpack('>IIBBBB', by_type[CHUNK_IHDR][0])
    has_alpha = bool(flags & 1)
    is_hdr    = bool(flags & 2)
    ch = 4 if has_alpha else 3

    rmap_list = by_type.get(CHUNK_RMAP, [])
    images = []
    base = None
    rmap_idx = 0

    for ct, data in chunks:
        if ct == CHUNK_FDAT:
            rmap = rmap_list[rmap_idx] if rmap_idx < len(rmap_list) else None
            rmap_idx += 1
            frame = _decode_full_frame(data, rmap, w, h, cmode, ch, is_hdr)
            base = frame
            images.append(frame.copy())
        elif ct == CHUNK_FDLT:
            if base is None:
                raise ValueError("Delta frame before full frame")
            x0, y0, dw, dh = struct.unpack('>IIII', data[:16])
            frame = base.copy()
            if dw > 0 and dh > 0:
                region = _decompress_block(data[16:], (dw, dh), ch, is_hdr)
                frame.paste(region, (x0, y0))
            base = frame
            images.append(frame)

    return images


def decode_metadata(input_path: str) -> dict:
    """Return {'exif': bytes|None, 'icc': bytes|None} from the MDAT chunk."""
    for ct, data in _read_all_chunks(input_path):
        if ct == CHUNK_MDAT:
            icc_len = struct.unpack('>I', data[:4])[0]
            icc = data[4:4 + icc_len] if icc_len else None
            ex_off = 4 + icc_len
            ex_len = struct.unpack('>I', data[ex_off:ex_off + 4])[0]
            ex = data[ex_off + 4:ex_off + 4 + ex_len] if ex_len else None
            return {'exif': ex, 'icc': icc}
    return {'exif': None, 'icc': None}


def decode_preview(input_path: str) -> Image.Image | None:
    """Return the embedded thumbnail from an express-mode file, or None.

    Reads only the PREV chunk — much faster than decode() over a slow network
    because the thumbnail is in the first few KB of the file.
    """
    with open(input_path, "rb") as f:
        if f.read(len(MAGIC)) != MAGIC:
            raise ValueError("Not a NOVA file")
        while True:
            ct, data = _read_chunk(f)
            if ct is None or ct == CHUNK_IEND:
                return None
            if ct == CHUNK_PREV:
                assert data is not None
                return Image.open(io.BytesIO(data)).convert("RGB")
            if ct == CHUNK_FDAT:
                return None   # no PREV chunk found before first frame


def decode_hdr16(input_path: str):
    """Return uint16 (H, W, 3) numpy array for N-marker frames, else None."""
    try:
        import numpy as np
    except ImportError:
        return None
    w = h = None
    for ct, data in _read_all_chunks(input_path):
        if ct == CHUNK_IHDR:
            w, h = struct.unpack('>II', data[:8])
        elif ct == CHUNK_FDAT and w is not None and data[0:1] == b'N':
            raw = zlib.decompress(data[1:])
            return np.frombuffer(raw, dtype='<u2').reshape(h, w, 3).copy()
    return None


# ── CLI ───────────────────────────────────────────────────────────────────────

def _fmt(n: int) -> str:
    return f"{n / 1024:.1f} KB" if n < 1_000_000 else f"{n / 1_048_576:.2f} MB"


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'help'

    if cmd == 'encode':
        src, dst = sys.argv[2], sys.argv[3]
        quality = int(sys.argv[4]) if len(sys.argv) > 4 else 85
        mode    = sys.argv[5] if len(sys.argv) > 5 else 'adaptive'
        encode(src, dst, quality=quality, mode=mode)
        s, d = os.path.getsize(src), os.path.getsize(dst)
        print(f"{src} ({_fmt(s)}) → {dst} ({_fmt(d)})  {d/s*100:.1f}%  [{mode} q{quality}]")

    elif cmd == 'decode':
        src, dst = sys.argv[2], sys.argv[3]
        frames = decode(src)
        if len(frames) == 1:
            frames[0].save(dst)
        else:
            frames[0].save(dst, save_all=True, append_images=frames[1:], loop=0)
        print(f"Decoded {len(frames)} frame(s) → {dst}")

    elif cmd == 'info':
        src = sys.argv[2]
        chunks = _read_all_chunks(src)
        for ct, data in chunks:
            if ct == CHUNK_IHDR:
                w, h, bd, cs, flags, cm = struct.unpack('>IIBBBB', data)
                print(f"Size      : {w}×{h}")
                print(f"Bit depth : {bd}")
                print(f"Alpha     : {bool(flags & 1)}  HDR: {bool(flags & 2)}  Animated: {bool(flags & 4)}")
                print(f"Comp mode : {['adaptive','lossless','lossy','express'][cm] if cm < 4 else '?'}")
            elif ct == CHUNK_ANIM:
                nf, dur, lp = struct.unpack('>IHH', data)
                print(f"Frames    : {nf}  {dur}ms/frame  loop={lp}")
            elif ct == CHUNK_MDAT:
                icc_len = struct.unpack('>I', data[:4])[0]
                ex_len  = struct.unpack('>I', data[4 + icc_len:8 + icc_len])[0]
                print(f"ICC       : {icc_len}B  EXIF: {ex_len}B")
        print(f"File size : {_fmt(os.path.getsize(src))}")

    elif cmd == 'bench':
        # bench <file> — compare all modes vs original
        src = sys.argv[2]
        s = os.path.getsize(src)
        print(f"Original  : {_fmt(s)}")
        for m in ('lossless', 'adaptive', 'lossy', 'express'):
            dst = f'/tmp/_nova_bench_{m}.nova'
            encode(src, dst, mode=m)
            d = os.path.getsize(dst)
            print(f"{m:9s} : {_fmt(d)}  ({d/s*100:.1f}%)")
            os.remove(dst)

    else:
        print("nova.py encode  <src> <dst> [quality=85] [adaptive|lossless|lossy]")
        print("nova.py decode  <src> <dst>")
        print("nova.py info    <src>")
        print("nova.py bench   <src>")
