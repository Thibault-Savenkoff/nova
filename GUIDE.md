# NOVA guide

Everything the `nova` command does, and how to choose. The file format itself is in [FORMAT.md](FORMAT.md);
installing and the viewer plugins are in [README.md](README.md).

- [The three modes](#the-three-modes)
- [Levels](#levels)
- [Quality: -q and -e](#quality--q-and--e)
- [What the encoder decides for you](#what-the-encoder-decides-for-you)
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
| 0 | Palette + context mixing on the indices | Fastest | Only for an image of 256 colours or less, else it is refused |
| 1 | Two direct models, one mixer | Fast | The baseline the others must beat |
| 2 | Adds hashed contexts | | Good middle ground, and what alpha planes use |
| 3 | Adds a second mixer | | |
| 4 | Adds a third mixer, error-selected | Slowest | Tried automatically only from 16 Mpx, where each % is megabytes |
| 5 | Wavelet, lossy (CDF 9/7) | Fast | Photos; takes `-q`, not `-e` |
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

## What the encoder decides for you

In adaptive mode, without `-l` or `-q`, the encoder makes five decisions. Each one is measured, never guessed:

1. **Photo or graphics**, by the repeated-pixel share above.
2. **Wavelet or exact**: a photo goes to level 5, unless coding it losslessly is within 10 % of the wavelet's
   size — smooth synthetic images pass the photo test but code smaller exactly.
3. **The level**, by trial on the central 512 × 512 (and the whole frame for the palette).
4. **The quality of a JPEG source**: the JPEG's own quality is estimated from its quantisation table and
   matched with `50 + Q/2`, capped at 90, so the file does not spend bits on the JPEG's artefacts.
   A JPEG q 50 gives 75, a q 70 gives 85.
5. **A second pass for grainy JPEGs**: if the result still takes over 85 % of the source JPEG, it is coded
   again 5 quality steps lower per 21 % too much, down to 60.

`-q`, `-l` or `-m lossless` each switch off the decisions they concern.

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
nova decode photo.nova photo.avif -hdr      # AVIF 10 bits, PQ
nova decode photo.nova photo.png -hdr       # PNG 16 bits, PQ
nova decode photo.nova photo.tif -hdr       # 16-bit float TIFF, linear, 1.0 = SDR white (for editors)
```

Without `-hdr`, you get the SDR image, which is what most screens and programs expect.

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
