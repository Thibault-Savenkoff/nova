# NOVA guide

Everything the `nova` command does, and how to choose. The file format itself is in [FORMAT.md](FORMAT.md);
installing and the viewer plugins are in [README.md](README.md).

- [The three modes](#the-three-modes)
- [Levels](#levels)
- [Quality: -q and -e](#quality--q-and--e)
- [How the encoder decides](#how-the-encoder-decides)
- [Encoding](#encoding)
- [Decoding](#decoding)
- [Animations](#animations)
- [HDR](#hdr)
- [Camera RAW](#camera-raw)
- [Metadata and Live Photos](#metadata-and-live-photos)
- [Speed](#speed)
- [Reading a file](#reading-a-file)
- [Recipes](#recipes)

## The three modes

`-m` picks how much the encoder may change the pixels.

| Mode | What it does | Use it for |
| --- | --- | --- |
| `adaptive` (default) | Decides per image: exact for graphics, wavelet for photos, and falls back to exact when the wavelet does not save at least 10 % | Everything, unless you have a reason |
| `lossless` | Never changes a pixel. Levels 0–4 only | Archiving, screenshots, art, anything you will edit again |
| `lossy` | Wavelet (level 5) on photos, near-lossless (`-e`) on graphics | Sharing, web pages, storage where size wins |

The "photo or graphics" test is mechanical: the share of pixels equal to their left neighbour in the first
frame. Under 65 % the image is treated as a photo. Photos measure 0–45 %, text, UI and screenshots 78–96 %.

## Levels

`-l` picks the codec, and how hard it works. Leave it out and the encoder measures which is smallest.

| Level | Codec | Speed | Notes |
| --- | --- | --- | --- |
| 0 | Palette: the image as one plane of colour indices, then context mixing | Fastest | Only for an image of 256 colours or less, else it is refused |
| 1 | MED prediction, 2 direct models, 1 mixer | Fast | The baseline the others must beat |
| 2 | + 5 hashed models, a 2nd mixer, an APM | | Graphics, text, UI; also what alpha planes and lossless gain maps use |
| 3 | + a blend of 5 predictors (NLMS) and cross-colour prediction | | Photos |
| 4 | + a wide 24-tap NLMS as 6th predictor, a 3rd mixer | Slowest | Tried automatically only from 16 Mpx, where each % is megabytes |
| 5 | Wavelet, lossy (YCoCg, CDF 9/7) | Fast | Photos; takes `-q`, not `-e`. Alpha stays exact |
| 6 | Camera sensor frame | | Not selectable: RAW sources get it on their own |

When you leave `-l` out, levels 1 to 3 are tried on the central 512 × 512 of the first frame (4 as well from
16 Mpx). Level 1 must be beaten by 3 % to be dropped, then the smallest wins. Level 0 is measured on the whole
frame, because a palette only works if the whole image fits one.

## Quality: -q and -e

Two different knobs, one per codec:

- **`-q 0-100`** is the wavelet quality, level 5 only. 90 (the default) is about 45 dB: visually lossless.
  75 is about 41 dB, 50 about 36 dB, 25 about 30 dB on photos.
- **`-e 1-64`** is the maximum error per sample for levels 1–4, called near-lossless: every sample of the
  decoded image is within `eps` of the source. `-e 2` (the default in lossy mode) is invisible and typically
  saves a third over lossless.

`-q 100` is not lossless: it is the finest wavelet step. For an exact file use `-m lossless`.

## How the encoder decides

Every choice below is made in this order, for every `nova encode`. None depends on the machine: the same
source and options always give the same file, byte for byte, on 1 core or 16, on Linux or Windows.

### 1. Reading the sources

- **Pixels** are loaded as 8-bit RGBA. A 10-bit HEIC (iPhone screenshots) is rounded to 8 bits: at most 2 of
  1024 steps change, invisible, and 16-bit planes would cost size for nothing visible.
- **Rotation:** a HEIC's rotation is applied to the pixels (libheif does it), so its EXIF orientation is reset
  to 1. A JPEG's pixels stay as the camera wrote them, with its orientation tag, as every other format does.
- **Alpha:** a 4th plane is stored only if at least one pixel of one frame is not fully opaque. An RGBA PNG
  that is opaque everywhere is stored as RGB.
- **Several sources** make an animation; they must all have the same size.
- **A RAW source** (a CR3 by its header, or any file that is not PNG, JPEG or HEIF and that LibRaw opens:
  NEF, ARW, DNG…) skips everything below: its sensor frame is stored exactly (level 6), with
  what LibRaw needs to develop it. `-m lossy` and `-l` are refused.

### 2. Photo or graphics

The share of pixels equal to their left neighbour, in the first frame. **Under 65 %: a photo.** Measured on
real images: photos 0–45 % (sensor noise makes neighbours differ), text, UI and screenshots 78–96 % (flat
areas). The threshold sits in the gap between the two.

### 3. The codec, per mode

| Mode | Photo | Graphics |
| --- | --- | --- |
| `adaptive` (default) | Wavelet, level 5 (unless step 4 keeps it lossless) | Lossless, best level 0–3 (4 from 16 Mpx) |
| `lossless` | Lossless, best level | Lossless, best level |
| `lossy` | Wavelet, level 5 | Near-lossless: best level, `-e 2` |

With `-l`, the level is yours and only the mode's rule for loss applies: `-l 5` is refused in lossless mode,
and `-l 1` to `-l 4` on a photo in adaptive mode gives near-lossless `eps 1` (a photo coded exactly at level
1–4 is rarely what someone forcing a level wants, and eps 1 is invisible). In lossy mode, `-l 1`–`-l 4` uses
`-e` (2 by default).

**Why a photo is not stored exactly by default.** Coding each pixel exactly keeps the sensor noise, and noise
does not compress. Worse, when the source is itself lossy (HEIC, JPEG), an exact copy spends bytes keeping
its compression artefacts. Measured on a 24 Mpx iPhone 17 Pro Max HEIC of 3.0 MB:

| | Size | Of the HEIC |
| --- | --- | --- |
| `nova encode IMG.HEIC` (adaptive: level 5, q 90) | 2.8 MB | 93 % |
| `nova encode IMG.HEIC -m lossless` (level 4) | 9.3 MB | 310 % |

q 90 is about 45 dB: no visible difference with the HEIC. Use `-m lossless` for a PNG or a RAW you will edit,
not to "keep the quality" of a HEIC or JPEG, which has already been decided by the phone.

### 4. Wavelet or exact, for photos in adaptive mode

Some images pass the photo test yet code smaller exactly: smooth gradients, renders, heavily denoised shots.
The encoder codes the central 512 × 512 both ways, lossless at the best level and wavelet at the chosen
quality. **Unless the wavelet saves at least 10 %, the image is stored lossless:** a smaller gain is not
worth losing exactness for. Only adaptive mode does this, and only without `-l`.

### 5. The quality of level 5

- **Default: q 90** (about 45 dB, visually lossless), or your `-q`.
- **A JPEG source without `-q`:** its own quality is estimated from its luminance quantisation table (as
  ImageMagick does) and the wavelet gets `50 + Q/2`, at most 90. A q 50 JPEG gives 75, a q 70 gives 85,
  a q 80 or more gives 90. Coding a low-quality JPEG at q 90 would faithfully keep its blocks and ringing:
  measured, it made files of 115–167 % of the JPEG; the matched quality adds at most 0.6 dB of loss.
  Only JPEG sources have a quantisation table to read; not done for animations.
- **A grainy JPEG:** if the file still takes over 85 % of the JPEG, it is coded once more, 5 quality steps
  lower per 21 % too much, never below 60. Film grain and noise cost more than the JPEG's quality says;
  each 5 steps saves about 21 %. A grainy q 85 JPEG: 117 % at q 90, 71 % at q 80.

### 6. The level, for lossless and near-lossless

Levels 1, 2 and 3 are tried on the **central 512 × 512** of the first frame (level 4 too from 16 Mpx: it is
the slowest, and only worth it where 1 % is megabytes). A sample is enough: the centre of an image is
representative, and the trials stay short whatever the image size.

- **Level 1 must be beaten by 3 %** to be dropped: it is the fastest to decode, so a gain under 3 % does
  not justify a slower level. Above level 1, the smallest wins.
- **Level 0 (palette)** is tried on the whole first frame, if all of it has 256 colours or less (one extra
  colour anywhere breaks a palette). Its size is scaled to the sample's for the comparison.
- In an animation, a later frame that brings more than 256 colours cannot use level 0: that region gets
  level 2.

### 7. What is stored besides the pixels

- **Thumbnail (`PREV`):** only for images over 2 Mpx whose long side exceeds 1024 px; smaller images decode
  in about a second anyway (a 1428 × 910 screenshot's preview was 16 % of its file). The thumbnail is 512 px,
  box-filtered, wavelet q 75. Its budget is 1 byte per 128 pixels of the image (16 KB for 1080p); over it,
  the quality drops to 56 (text-heavy screenshots), never lower.
- **Metadata of the first source:** EXIF (GPS included), XMP, ICC profile, PNG text chunks and other
  ancillary chunks, JPEG APP and COM segments, byte for byte. Pixel-structure chunks (tRNS, APNG frames)
  are not metadata and are not copied.
- **HDR gain map (`GMAP`)** of a still HEIC that has one: coded exactly (level 2) when the image is lossless,
  else with the wavelet at `-q` (90 by default). It takes 1–3 % of the file.
- **Live Photo video (`LIVE`)** given with `-live`, byte for byte.

### 8. Animations

The first frame is coded whole. Each next frame stores only the **rectangle that changed**, coded on top of
the previous frame *as the decoder will see it* (after loss, if any), so errors never add up from frame to
frame. An unchanged frame stores an empty rectangle and no pixels. The mode and level are decided on the first frame, for all.

### 9. Parallel stripes

Large images are cut into horizontal stripes coded and decoded independently: about 2 Mpx per stripe for
levels 1–4, 0.5 Mpx for level 5, 16 stripes at most. The count comes from the image size only, never from
the number of cores, which is why the file is identical everywhere. A stripe restarts its models, which costs a
little size, the price of decoding on every core.

`-q`, `-l`, `-e` and `-m` each switch off the decisions they concern; nothing else changes them.

## Encoding

```sh
nova encode <sources...> [out.nova] [options]
```

Leave the destination out and it is derived from the first source, next to it: `photo.jpg` gives `photo.nova`.
If that file already exists and you are on a terminal, the encoder asks: `[r]` replace, `[n]` a new name
(`photo-1.nova`, `photo-2.nova`, …), `[c]` cancel. In a script, with no terminal, it replaces as before.

Sources: PNG, JPEG, HEIC, HEIF, AVIF (needs libheif), camera RAW (needs LibRaw). Several sources make an
animation. Options: `-m`, `-l`, `-q`, `-e`, `-d ms` (frame delay), `-live file.mov`.

The encoder always writes, without being asked:

- a **512 px thumbnail** (`PREV`) for images over 2 Mpx, so a viewer shows something at once;
- the **metadata of the first source**: EXIF with GPS, XMP, the ICC colour profile, PNG text chunks;
- the **HDR gain map** of an iPhone photo, when there is one.

## Decoding

```sh
nova decode <in.nova> <out.ext> [options]
```

The output format comes from the extension: `.png`, `.tif`/`.tiff`, `.jpg`/`.jpeg`, `.webp`, `.avif`,
`.heic`/`.heif`, `.pam` (raw RGBA). Options:

| Option | Meaning |
| --- | --- |
| `-q 1-100` | Quality of the output file. Defaults: JPEG and WebP 90, AVIF 85, HEIC 60 (about 44 dB) |
| `-m lossy\|lossless` | For WebP, AVIF and HEIC. The default follows the `.nova`: a lossless file stays lossless |
| `-fast` | WebP about 4× faster, files 2–6 % larger |
| `-hdr` | The HDR rendition, see below |

Decoding is exact: PNG and TIFF give back the pixels the encoder stored, whatever the level.

## Animations

Several sources make one file. Frames after the first store only the rectangle that changed, coded on top of
the previous frame as the decoder will see it.

```sh
nova encode frame*.png anim.nova -d 40      # 40 ms between frames
nova decode anim.nova out.png               # writes out_000.png, out_001.png, ...
```

The numbering keeps your extension (`out_000.jpg` for a `.jpg` output). Viewers with the Qt or glycin plugin
play the animation; gdk-pixbuf shows the first frame.

## HDR

An iPhone HEIC carries an HDR gain map (ISO 21496-1). NOVA keeps it, for 1–3 % of the file size.

```sh
nova decode photo.nova photo.jpg            # Ultra HDR JPEG (the gain map travels with it)
nova decode photo.nova photo.avif           # AVIF with the gain map (needs libavif 1.2+)
nova decode photo.nova photo.avif -hdr      # AVIF 10 bits, PQ
nova decode photo.nova photo.png -hdr       # PNG 16 bits, PQ
nova decode photo.nova photo.tif -hdr       # 16-bit float TIFF, linear, 1.0 = SDR white (for editors)
```

**To look at or share the photo, keep the gain map: `.jpg` or `.avif`, without `-hdr`.** They hold the SDR
image, which every viewer shows as the iPhone does, and the gain map, which HDR screens apply. A lossless
`.nova` (a screenshot) still gives a lossless AVIF, without the gain map; `.heic` has none either (libheif
cannot write it).

`-hdr` writes the HDR rendition itself, in absolute brightness (PQ, SDR white = 203 nits). It is for HDR
editors and players: a viewer that does not tone map PQ to its screen, such as Gwenview on an SDR screen,
shows it burnt, with cyan skies. The AVIF and HEIC carry the light levels (`clli`, `mdcv`) that players tone
map by. Without `-hdr`, PNG, TIFF and HEIC get the SDR image only.

## Camera RAW

A RAW source keeps the sensor frame exactly (level 6), plus what LibRaw needs to develop it.

```sh
nova encode IMG_1401.CR3 IMG_1401.nova
nova decode IMG_1401.nova IMG_1401.dng                     # back to DNG
nova decode IMG_1401.nova out.tif                          # developed, 16 bits
nova decode IMG_1401.nova out.png -look darktable          # developed with darktable's look
nova decode IMG_1401.nova sensor.pgm                       # the bare sensor frame
```

`-look canon` (the default) follows the camera's rendering; `-look darktable` follows darktable's.

## Metadata and Live Photos

EXIF (GPS included), XMP, the ICC profile and PNG text survive a round trip, and come back in the output
format that can hold them. The EXIF orientation is **kept as written**: the pixels stay as the camera wrote
them and viewers rotate, as every other format does.

A Live Photo's video rides along:

```sh
nova encode IMG_0042.HEIC out.nova -live IMG_0042.mov
nova decode out.nova out.png                # writes out.png + out.mov
```

## Speed

Images are cut into stripes coded and decoded in parallel, one process per stripe (0.5 to 2 Mpx each
depending on the codec, 16 at most). `NOVA_THREADS=n` caps the processes; `NOVA_THREADS=1` runs everything in one process and gives exactly
the same file. Windows uses copies of the process instead of `fork`, with the same result.

A 7.7 Mpx photo takes about 3 s to encode at level 5 and 2.5 s to decode on a 12-core machine; level 4 is the
slow one, which is why it is only tried from 16 Mpx. `nova preview` is instant whatever the size.

## Reading a file

```sh
nova info photo.nova       # chunks, sizes, level, frames, gain map
nova preview photo.nova thumb.png
nova bench photo.png ...   # lossless size and bits per pixel of each source, without writing a file
```

## Recipes

```sh
# A screenshot for a bug report, exact and small
nova encode shot.png shot.nova -m lossless

# A photo for a web page, smaller than the JPEG it came from
nova encode photo.jpg photo.nova -m lossy

# The same photo, visibly untouched but as small as possible
nova encode photo.heic photo.nova -q 85

# An icon or pixel art with few colours
nova encode icon.png icon.nova -l 0

# A photo you will edit later: exact pixels, the camera's metadata
nova encode IMG_1398.HEIC IMG_1398.nova -m lossless

# Back to a shareable file
nova decode IMG_1398.nova IMG_1398.jpg -q 92
```
