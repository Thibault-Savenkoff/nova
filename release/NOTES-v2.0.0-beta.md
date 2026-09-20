NOVA v2 is a rewrite from scratch in [Lisaac Ω](https://lisaac.org), with its own codec.
v1 was a Python container around PNG and JPEG data; v2 codes the pixels itself.

This is a **beta**: the format is feature-complete and the test suite passes, but
`.nova` files written by this build are not guaranteed to be readable by v2.0.0
final. Do not use it as the only copy of anything you care about.

**v1 and v2 files are not compatible**, in either direction.

## What v2 does

- **Lossless** — every pixel comes back exactly, at about **50 %** of an optimised PNG
  on photos and **27 %** on a terminal screenshot; **84 %** of WebP lossless on average.
- **Lossy** — a wavelet codec at equal PSNR/SSIM: **69 %** of a WebP, on par with AVIF and HEIC.
- **Camera RAW** — the sensor frame of a CR3 kept bit for bit in 80–85 % of the CR3's size,
  and written back out as a DNG or developed with the camera's look.
- **HDR** — the iPhone gain map (ISO 21496-1) is kept and written back as an Ultra HDR
  JPEG or AVIF, or applied for PQ output.
- **Animation**, **EXIF/XMP/ICC**, and an embedded 512 px thumbnail viewers show at once.

## Install

Linux and macOS (Intel and Apple Silicon):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash
```

Installs `nova` and its shell completion into `~/.local`, registers the `.nova` file type,
and offers to build the viewer plugins for your desktop. `--system` installs into
`/usr/local`, `--no-plugins` skips the viewers, `-y` skips every prompt.
To remove everything it installed, and nothing else:

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash -s -- --uninstall
```

Windows: build the installer with `win/dist.sh` (MinGW + NSIS). No prebuilt `.exe` in this
pre-release.

Browser: nothing to install — [the web page](https://thibault-savenkoff.github.io/nova/)
still runs v1 until v2 reaches `main`.

Verify a download against its `.sha256` next to it.

## Known limits

- **Windows Photos** and the **iOS Photos** app accept no third-party codec, whatever the
  format. On Windows, `.nova` opens in Windows Photo Viewer instead.
- **macOS has no Finder or Quick Look support** — the CLI is tested and works; a native
  ImageIO plugin is not written yet.
- **Nautilus does not generate `.nova` thumbnails** on GNOME, though Loupe opens the files
  and double-click works. Being looked at.
- **IrfanView** is untested; XnView MP works.

## Reporting

Please open an issue with the file, the command, and `nova info file.nova`.
