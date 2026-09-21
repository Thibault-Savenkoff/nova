Second beta. The first one shipped Linux and macOS binaries only, and its Windows
package — built by hand — turned out to be broken in ways a real Windows machine
found immediately. This release is the result of testing it there.

Still a **beta**: `.nova` files written by this build are not guaranteed to be
readable by v2.0.0 final, and **v1 and v2 files are not compatible** either way.

## What changed

- **Windows binaries are part of the release now** (`nova-setup.exe`, `nova-setup.msi`
  and `nova-windows.zip`, built by CI instead of by hand). 64-bit Intel/AMD only:
  the WIC codec cannot load on a Windows ARM64 machine.
- **Camera RAW works on Windows.** LibRaw and its dependencies are in the package;
  before, `nova encode photo.CR3` refused every RAW file.
- **`nova` no longer silently did nothing** when the install directory was on the
  `PATH`: PowerShell resolved the name to the completion script rather than to
  `nova.exe`. The script is `nova-completion.ps1` now.
- **Tab completion is an optional component of the installer**, and the
  uninstaller takes its line back out.
- `install.bat` in the zip asks for administrator rights itself instead of failing
  with `0x80040201`.
- The package is a third of its previous size: its DLLs were shipped unstripped.

Nothing changed in the codec or the file format since `v2.0.0-beta`.

## Install

Linux and macOS (Intel and Apple Silicon):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash
```

`--system` installs into `/usr/local`, `--no-plugins` skips the viewers, `-y` skips
every prompt. To remove everything it installed, and nothing else:

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash -s -- --uninstall
```

Windows: `nova-setup.exe`, or `nova-setup.msi` for deployment tools, or the zip for
no installer at all. Verify a download against its `.sha256` where there is one.

Browser: [the web page](https://thibault-savenkoff.github.io/nova/) still runs v1
until v2 reaches `main`.

## Known limits

- The Windows installers are **not code-signed**, so SmartScreen shows "unknown
  publisher", and Defender currently reports `Trojan:Win32/Wacatac.C!ml` — a
  machine-learning false positive on unsigned NSIS installers, submitted to
  Microsoft.
- **HEIC and AVIF do not work on Windows**: nova loads libheif at run time and
  there is no MinGW build of it to ship. Put `libheif.dll` next to `nova.exe` and
  they start working. They work normally on Linux and macOS.
- **Windows Photos** and the **iOS Photos** app accept no third-party codec:
  `.nova` opens in Windows Photo Viewer instead, and shows blank in Photos.
- **macOS has no Finder or Quick Look support** — the CLI works; a native ImageIO
  plugin is not written yet.
- **Nautilus does not generate `.nova` thumbnails** on GNOME, though Loupe opens
  the files and double-click works.

## Reporting

Please open an issue with the file, the command, and `nova info file.nova`.
