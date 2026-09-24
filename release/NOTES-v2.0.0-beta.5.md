Fifth beta. One feature: **`nova convert`**, any image to any format in one
command.

Still a **beta**: `.nova` files written by this build are not guaranteed to be
readable by v2.0.0 final, and **v1 and v2 files are not compatible** either way.

## What changed

- **`nova convert <source> <destination>`** reads what `nova encode` reads (PNG,
  JPEG, HEIC, AVIF, camera RAW) and writes what `nova decode` writes (PNG, TIFF,
  JPEG, WebP, AVIF, HEIC, DNG), with no `.nova` in between:

  ```sh
  nova convert IMG_1152.HEIC IMG_1152.jpg     # EXIF, colour profile and HDR gain map kept
  nova convert IMG_1398.CR3 IMG_1398.dng      # camera RAW straight to DNG
  ```

  The pixels and metadata go straight from the reader to the writer, so the
  result is exactly what `encode -m lossless` then `decode` would give, only
  faster: a 7.7 Mpx JPEG to PNG in 0.7 s, a Canon CR3 to DNG in 1.2 s. It takes
  `decode`'s options (`-q`, `-m`, `-hdr`, `-look`...). Without `-m`, a WebP,
  AVIF or HEIC output is lossless when the source was (PNG, TIFF) and lossy
  otherwise. Tab completion knows it in bash, zsh, fish and PowerShell.
- **The time in "Done: wrote ... in"** no longer counts the time spent answering
  the "file exists" prompt.
- Install script (Linux and macOS):
  - Run from an unpacked release archive (`./install.sh`), it installs that
    archive instead of downloading the latest release.
  - It keeps a copy of itself, so uninstalling works offline and with the
    install's own `--prefix` or `--system` (the command is printed at the end).
  - With the KDE thumbnailer installed, Dolphin no longer lists NOVA twice in its
    preview settings.

Nothing changed in the codec or the file format since `v2.0.0-beta`.

## Install

Linux (x86_64 and arm64) and macOS (Intel and Apple Silicon):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash
```

`--system` installs into `/usr/local`, `--no-plugins` skips the viewers, `-y` skips
every prompt. From a downloaded archive, no network: unpack it and run
`./install.sh` inside, or `install.sh --from nova-<version>-<os>-<arch>.tar.gz`.
To remove everything it installed, and nothing else:

```sh
bash ~/.local/share/nova/install.sh --uninstall     # add --system or --prefix DIR if you installed with it
```

Windows (64-bit): the `-setup.exe`, or the `.msi` for deployment tools, or the
`.zip` for no installer at all.

Verify any download against its `.sha256`: `sha256sum -c <file>.sha256`, or
`Get-FileHash <file>` in PowerShell.

Browser: [the web page](https://thibault-savenkoff.github.io/nova/) still runs v1
until v2 reaches `main`.

## Known limits

- The Windows installers are **not code-signed**, so SmartScreen shows "unknown
  publisher", and Defender may report `Trojan:Win32/Wacatac.C!ml` — a
  machine-learning false positive on unsigned NSIS installers. Each new build is
  judged afresh.
- **Windows Photos** and the **iOS Photos** app accept no third-party codec:
  `.nova` opens in Windows Photo Viewer instead, and shows blank in Photos.
- **macOS has no Finder or Quick Look support** — the CLI works; a native ImageIO
  plugin is not written yet.
- **Nautilus does not generate `.nova` thumbnails** on GNOME, though Loupe opens
  the files and double-click works.
- No Windows on ARM build yet.

## Reporting

Please open an issue with the file, the command, and `nova info file.nova`.
