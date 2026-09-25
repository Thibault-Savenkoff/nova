Eighth beta: **smaller lossy photos with truer colours**, much faster thumbnails in KDE and GNOME,
and fixes for the upgrade from NOVA.

Still a **beta**: `.yaif` files written by this build are not guaranteed to be readable by v2.0.0
final, and **v1 and v2 files are not compatible** either way.

## What changed

- **Lossy photos: 12 % smaller at the same visual quality.** Measured on the 24 Kodak test images
  with SSIMULACRA2 (a perceptual metric), against AVIF: YAIF files were 31 % larger than AVIF, now
  19 %. The colour planes are quantised more finely and the finest detail a little more coarsely:
  at the same file size, greens and browns no longer drift toward grey. `-q 90` still looks
  identical to the source, and its files are about 4 % smaller.
- **Files written by earlier betas still open**, pixel for pixel as before. Files written by this
  one need beta.8 or later: an older `yaif` refuses them instead of showing them wrong.
- **Thumbnails up to 13 times faster** in Dolphin, Gwenview and GNOME (gdk-pixbuf): a thumbnail is
  now made from the 512 px preview stored in every file over 2 megapixels, instead of decoding the
  whole image (Windows Explorer already did this).
- **`yaif encode` names the method** instead of a bare level number: `wavelet, q 90`,
  `lossless, predictive 2/4`, `lossless, palette`, `RAW, lossless`. `yaif info` shows it for each
  frame, with the level number.
- **Upgrading from NOVA**:
  - zsh completion did not work after installing YAIF over NOVA (zsh kept a stale cache).
    `install.sh` now clears it. Already hit? Run `rm -f ~/.zcompdump*; exec zsh`.
  - `install.sh` now really ticks YAIF in Dolphin's thumbnail settings (it wrote the wrong plugin
    name, so the box stayed unticked).
- **Qt plugin built by hand** (`cmake -B build -S plugins/qt`) is now optimised by default; it
  decoded about 3 times slower.
- **Web page**: shows up sooner on phones, and the logo lost its gap between Y and A and the thin
  line that split the Y at 100 % zoom.

## Install

Linux (x86_64 and arm64) and macOS (universal):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/yaif/v2/install.sh | bash
```

`--system` installs into `/usr/local`, `--no-plugins` skips the viewers, `-y` skips every prompt.
From a downloaded archive, no network: unpack it and run `./install.sh` inside, or
`install.sh --from yaif-<version>-<os>-<arch>.tar.gz`. To remove everything it installed, and
nothing else:

```sh
bash ~/.local/share/yaif/install.sh --uninstall     # add --system or --prefix DIR if you installed with it
```

Windows (64-bit): the `-setup.exe`, or the `.msi` for deployment tools, or the `.zip` for no
installer at all.

**Verify a download** against `SHA256SUMS` (attached, and listed below):

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

Browser: [the web page](https://thibault-savenkoff.github.io/yaif/) still runs v1 until v2 reaches
`main`.

## Known limits

- The Windows installers are **not code-signed**, so SmartScreen shows "unknown publisher", and
  Defender may report `Trojan:Win32/Wacatac.C!ml` — a machine-learning false positive on unsigned
  NSIS installers. Each new build is judged afresh.
- **Windows Photos** and the **iOS Photos** app accept no third-party codec: `.yaif` opens in
  Windows Photo Viewer instead, and shows blank in Photos.
- **macOS has no Finder or Quick Look support** — the CLI works; a native ImageIO plugin is not
  written yet.
- **Nautilus does not generate `.yaif` thumbnails** on GNOME, though Loupe opens the files and
  double-click works.
- No Windows on ARM build yet.

## Reporting

Please open an issue with the file, the command, and `yaif info file.yaif`.
