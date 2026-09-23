Third beta. It finishes Windows: every format nova reads and writes elsewhere now
works there too, and the installers set everything up on their own.

Still a **beta**: `.nova` files written by this build are not guaranteed to be
readable by v2.0.0 final, and **v1 and v2 files are not compatible** either way.

## What changed

- **HEIC and AVIF work on Windows, reading and writing**, HDR gain map included:
  `nova decode photo.nova photo.avif` writes the same ISO 21496-1 gain map as on
  Linux and macOS. libheif, libde265, kvazaar, aom and libavif are now built for
  Windows and shipped in the package.
- **Linux on ARM** (Raspberry Pi, ARM servers): new `linux-arm64` archive, and the
  install script picks it up by itself.
- **Tab completion is set up by both Windows installers**, for Windows PowerShell
  and PowerShell 7, and works in the next terminal you open. The line added to your
  profile is appended, never rewritten, so a profile with accented characters is
  left intact; uninstalling takes it back out.
- The `.msi` no longer fails with **error 2762** when uninstalling.
- The `.exe` installs into `Program Files`, not `Program Files (x86)`: nova is
  64-bit. Uninstall a previous beta first, or its old folder stays behind.
- Extensions are case-insensitive: `IMG.JPG`, `OUT.PNG` or `photo.NOVA`
  used to be rejected or misread.
- `nova decode` asks before overwriting an existing file, as `encode` already did:
  replace, pick a new name (`out-1.png`), or cancel.
- Settings > Apps shows the real version for both installers.
- Every download is named `nova-<version>-<os>-<arch>` and has its `.sha256`,
  Windows included.
- Building from the **"Source code"** archive with `build.sh` now installs the
  completions, plugins and docs; it used to install the bare binary without a word.

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
`.zip` for no installer at all. The package grew from 3 to 8.5 MB: most of it is
the AV1 encoder.

Verify any download against its `.sha256`: `sha256sum -c <file>.sha256`, or
`Get-FileHash <file>` in PowerShell.

Browser: [the web page](https://thibault-savenkoff.github.io/nova/) still runs v1
until v2 reaches `main`.

## Known limits

- The Windows installers are **not code-signed**, so SmartScreen shows "unknown
  publisher", and Defender may report `Trojan:Win32/Wacatac.C!ml` — a
  machine-learning false positive on unsigned NSIS installers. It has been
  submitted to Microsoft, but each new build is judged afresh.
- **Windows Photos** and the **iOS Photos** app accept no third-party codec:
  `.nova` opens in Windows Photo Viewer instead, and shows blank in Photos.
- **macOS has no Finder or Quick Look support** — the CLI works; a native ImageIO
  plugin is not written yet.
- **Nautilus does not generate `.nova` thumbnails** on GNOME, though Loupe opens
  the files and double-click works.
- No Windows on ARM build yet.

## Reporting

Please open an issue with the file, the command, and `nova info file.nova`.
