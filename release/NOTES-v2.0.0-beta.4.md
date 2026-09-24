Fourth beta. One feature: **a HEIC now keeps the photo's HDR**, as the JPEG and
AVIF already did.

Still a **beta**: `.nova` files written by this build are not guaranteed to be
readable by v2.0.0 final, and **v1 and v2 files are not compatible** either way.

## What changed

- **`nova decode photo.nova photo.heic` writes the HDR gain map** (ISO 21496-1)
  of an iPhone photo: an HDR screen shows the HDR, every other one the normal
  picture. Until now only `.jpg` and `.avif` kept it.
  No released libheif can write one yet, so nova uses **libnova-heif**: libheif
  with its gain-map pull request
  ([strukturag/libheif#1503](https://github.com/strukturag/libheif/pull/1503)), built only for this. Reading HEIC still
  goes through your system's libheif and its security updates.
  - **Windows**: included in the installers and the zip.
  - **Linux and macOS**: the install script builds it (1–3 minutes). It needs
    cmake and a C/C++ compiler; when they are missing it says what to install and
    carries on, and `.heic` output stays SDR. `--no-heic-hdr` skips it.
- The install script no longer compiles with an unlimited number of parallel
  jobs, which could run a machine out of memory when building the viewer plugins.

Nothing changed in the codec or the file format since `v2.0.0-beta`.

## Install

Linux (x86_64 and arm64) and macOS (Intel and Apple Silicon):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash
```

`--system` installs into `/usr/local`, `--no-plugins` skips the viewers, `-y` skips
every prompt. To remove everything it installed, and nothing else:

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash -s -- --uninstall
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
