# The YAIF image format, version 2

This document describes `.yaif` files: the container byte by byte, and the structure of each coded
stream. The entropy model (context mixing) is too detailed for prose to be exact, so its reference is
the decoder source: [`docs/yaif_decode.js`](docs/yaif_decode.js) (~1200 lines, levels 0-5) and the
`yaif` program (`yaif_*.li`, all levels). Every section below names the functions that implement it.
Two decoders written from these sources give the same pixels bit for bit (`test/js.sh`).

All integers are **big-endian**. `u8`, `u16`, `u32` are unsigned; sizes are in bytes.

## 1. File layout

```
signature   9 bytes   89 59 41 49 46 0D 0A 1A 0A   ("\x89YAIF\r\n\x1a\n", like PNG's)
chunk*      until the end of the file (or an IEND chunk)
```

Each chunk:

```
u32  type     four ASCII letters, e.g. "IHDR" = 0x49484452
u32  length   of data
     data     length bytes
u32  crc      CRC-32 (PNG/zlib polynomial 0xEDB88320) of type + data (not of length)
```

The order is type first, then length (PNG has the opposite order). A decoder must check every CRC and
must **skip chunk types it does not know**: new optional chunks can be added without breaking readers.

Chunk order written by `yaif` (`yaif.li`, `encode_frames`):

`IHDR`, `MDAT`*, `ANIM` (animations), `PREV` (thumbnail), `GMAP` (HDR), `FDAT`, `FDLT`* (animations),
`LIVE`. RAW files: `IHDR`, `RAWH`, `MDAT`*, `PREV`, `FDAT`. `IEND` is optional (not written: every chunk
has a length and CRC, and the frame count is checked). Readers should rely on types, not positions,
except that `IHDR` comes first and frames come in display order.

## 2. IHDR: image header (12 bytes, required, first)

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | width (1-65535) |
| 4 | u32 | height (1-65535) |
| 8 | u8 | bits per sample: 8 (images), 16 (RAW sensor frame) |
| 9 | u8 | planes: 3 (RGB), 4 (RGBA), 1 (RAW CFA) |
| 10 | u8 | **format version: 2** |
| 11 | u8 | flags: 4 = animated, 8 = RAW sensor frame (see `RAWH`) |

**Versioning rule.** The version byte changes only when a version-2 decoder could no longer read the
file correctly (a new coding of pixels, a changed meaning). Decoders must refuse other versions with a
clear message (`yaif`: "unsupported YAIF version (only v2)"). Everything that old decoders can safely
ignore is added as a new chunk type instead, without changing the version. Version 1 was an earlier,
unrelated container (PNG/JPEG inside); it is not readable as version 2.

## 3. Frames: FDAT and FDLT

`FDAT` holds a whole frame as one **coded region** (section 5) covering the image, `width x height`.

Animations (`IHDR` flag 4) have one `FDAT` then one `FDLT` per following frame:

```
u32 x0, u32 y0, u32 w, u32 h    changed rectangle (w = h = 0: frame identical to the previous one)
coded region                     the rectangle, coded over the previous frame as it was decoded
```

The rest of the frame is the previous frame. A frame is always the previous *decoded* frame plus the
rectangle: lossy frames stay consistent with the decoder.

## 4. Other chunks

| Type | Content |
|---|---|
| `ANIM` | `u32` frame count, `u16` delay in ms, `u16` loop count (0 = forever). Decoders must check they got that many frames. |
| `PREV` | Thumbnail: `u16 w`, `u16 h`, `u8` planes (3/4), coded region. Long side 512 px, written only for images over 2 Mpx whose long side exceeds 1024. Lets viewers show something at once. |
| `GMAP` | HDR gain map (ISO 21496-1, as in iPhone HEIC and Ultra HDR JPEG): `u16 w`, `u16 h`, `u8` planes (3), `u16 n`, `n` bytes of ISO 21496-1 metadata, coded region. Stills only. |
| `MDAT` | One metadata block: `u32 kind`, payload as in the source file. Kinds: PNG chunk types (`eXIf`, `iCCP`, `iTXt`, `tEXt`…) or JPEG segments (`APP0`-`APPF`, `COM `) with their payload (e.g. `APP1` = `"Exif\0\0"` + TIFF, `APP2` = `"ICC_PROFILE\0"` + index + count + profile). HEIC metadata is stored as `APP1`/`APP2`. EXIF orientation is kept as written: **pixels are stored as the camera wrote them**, viewers apply the orientation. |
| `LIVE` | The Live Photo video file (`.mov`) as it is (option `-live`). |
| `RAWH` | RAW sensor frame parameters (CFA pattern, black/white levels, colour matrices, white balance…): LibRaw's structures as saved by `yaif_rawin.li` (`nr_save`), read back by `nr_restore`. Version byte first. |
| `IEND` | Empty, optional end marker. |

## 5. Coded region

A coded region is `w x h` pixels of `np` planes (the frame, a rectangle, the thumbnail or the gain
map). It starts with two bytes:

```
u8 level    0-6
u8 param    level 0: unused; levels 1-4: eps (0 = lossless, else near-lossless: |error| <= eps);
            level 5: quality 0-100, + 128 for the current steps (see 5.4)
```

Decoder entry point: `decodeRegion` (`docs/yaif_decode.js`), `Yaif_codec.decode` (`yaif_codec.li`).

### 5.1 Planes and colour transform (levels 0-4)

Pixels are coded as planes, interleaved pixel by pixel: `G`, `R - G + 255`, `B - G + 255` (0-510, no
wrap-around), then `A` when `np = 4`. Samples are predicted from causal neighbours W, N, NW, NE, WW, NN.

### 5.2 Level 0: palette

```
u8 n-1               palette size (1-256)
n x np bytes         colours (R, G, B[, A])
stream               the palette indices as one plane, coded like level 2 (lossless)
```

### 5.3 Levels 1-4: predictive context mixing (lossless or near-lossless)

```
u8 ns                stripe count (1-16)
ns x (u32 length, stream)
```

The region is cut into `ns` horizontal stripes of `ceil(h / ns)` rows (the last one shorter), each an
independent stream (models restarted, rows of other stripes unused): stripes decode in parallel.

Per sample: a prediction (level 1-2: MED; level 3: blend of MED, averages, gradient and one NLMS
predictor weighted by recent errors; level 4: two NLMS predictors), the colour-cross correction on
chroma planes (level 3+), then the residual is binarised (zero flag, sign, exponent, mantissa bits) and
each bit coded with probabilities from the model: 2 direct and up to 5 hashed contexts (neighbour
values, errors, other planes of the pixel), a match model (finds the same neighbourhood earlier in the
region, like LZ77 for repeated patterns), two logistic mixers (three at level 4) and an APM. Level 1
uses the 2 direct contexts and one mixer only. Near-lossless: residuals quantised by `2 eps + 1`.

Reference: `Codec.codeRegion`, `predict`, `blend`, `nlms`, `setContexts`, `codeResidual`,
`matchStep` (JS); `yaif_codec.li`, `yaif_model.li`.

### 5.4 Level 5: wavelet (lossy photos)

```
RGB:   u8 ns, ns x (u32 length, stream)      ns: stripe count (1-16), + 128 when the chroma filter applies
RGBA:  u32 n, the RGB part above (n bytes), then the alpha plane as a coded region (levels 1-4, lossless)
```

- Colour: a YCoCg-style transform on samples scaled by 64 (inverse: `lossyFinish`, R = Y + Co - Cg, G = Y + Cg, B = Y - Co - Cg).
- Transform: CDF 9/7 lifting in integers (constants 1817, 3616, -217, -6497 over 4096), up to 6 levels
  while each side stays >= 16 samples (`waveletLevels`, `waveletInverse`).
- Quantisation: step from the quality (`lossyStep`: table `POW_T`, finer for coarser levels), dead-zone
  reconstruction offset 26/256 (`lossyPlane`). Quality byte >= 128 (written from 2.0.0-beta.8 on):
  quality = byte - 128, chroma steps x 300/256 and 246/256, finest detail bands (level 0) x 340/256.
  Below 128 (earlier files, still read): chroma x 512/256 and 420/256, no finest-band factor.
- Stripes: `ns` stripes of rows multiple of `2^levels` (`lossyRows`), independent streams.
- Chroma filter, when bit 7 of `ns` is set (written from 2.0.0-beta.9 on) and quality < 85: after the
  inverse transform, Co and Cg are each pulled toward a linear fit of chroma on luma over 5 x 5
  windows (a guided filter), with strength 64/64 up to quality 50 and `(85 - q) * 64 / 35` above.
  Exact integers; the reference is `chromaFilter` (`docs/yaif_decode.js`), whose values every decoder
  must reproduce bit for bit (edges replicated, floor divisions).
- Coefficients: low band with MED prediction, then high bands coarse to fine (HL, LH, HH). The finest
  bands carry one zero flag per 2x2 block of positions (all three planes). Contexts: neighbours, parent band, the other
  orientations, the luma plane for chroma. Reference: `Lossy.decodeStripe`, `codeBand`, `codeFlags`,
  `codeCoef`, `setContexts`.

### 5.5 Level 6: RAW sensor frame (lossless)

`[u8 ns] ns x (u32 length, stream)`: 16-bit CFA samples, each predicted by the mean of its same-colour
neighbours (2 apart), residuals coded with the level 5 binarisation and brightness / activity / other
colour contexts, in stripes of even row counts. Reference: `yaif_raw.li` (not in the JavaScript
decoder: viewers show the `PREV` thumbnail of RAW files).

## 6. Entropy coder

Binary range coder, 32-bit, carry-less, with 12-bit probabilities (`Model.codeBit`): `bound = (range >>>
12) * (4096 - p)`; normalise while `range < 2^24`. The stream starts with 4 bytes of `code`. Reading past
the end returns zeros; more than 4 bytes past it means a corrupt stream.

Probabilities come from counters (16-bit probability + count, adaptive rate `131072 / (2n + 3)`),
mixed in the logistic domain (`stretch` / `squash`, table `SQUASH_T`), then refined by an APM. All
arithmetic is integer; products that can exceed 32 bits are 64-bit (`yaif_decode.js` uses doubles, exact
below 2^53). Reference: `Model` (JS), `yaif_model.li`.

## 7. Decoding checklist

1. Check the signature, every CRC, and `IHDR` (version 2, sizes, bits, planes).
2. Skip unknown chunk types.
3. Decode `FDAT` (and `FDLT` for animations) with the coded region decoder. Check the `ANIM` frame count.
4. Apply the EXIF orientation (`MDAT` `eXIf` or `APP1` Exif) when showing the image; keep the ICC
   profile (`MDAT` `iCCP` or `APP2`) for colour.
5. Optional: `PREV` for a quick first view, `GMAP` for HDR screens.

Test files: `docs/samples/` (a photo with a gain map, a screenshot, an animation) and `test/corpus/`.
