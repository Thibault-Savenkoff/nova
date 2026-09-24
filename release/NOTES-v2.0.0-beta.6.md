Sixth beta. No codec or format changes — just a trimmed release page.

Still a **beta**: `.nova` files written by this build are not guaranteed to be
readable by v2.0.0 final, and **v1 and v2 files are not compatible** either way.

## What changed

- **Fewer, clearer download assets** (14 → 7): one file per platform, plus one
  shared `SHA256SUMS` instead of a `.sha256` next to every archive.
- **macOS is now a single universal binary** (`nova-2.0.0-beta.6-macos-universal.tar.gz`),
  running natively on both Apple Silicon and Intel — no more picking an
  architecture.
- Windows keeps its three forms: `-setup.exe`, `.msi` (for deployment tools),
  and `.zip` (no installer).

## Install

Linux (x86_64 and arm64) and macOS (universal):

```sh
curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/nova/v2/install.sh | bash
```

`--system` installs into `/usr/local`, `--no-plugins` skips the viewers, `-y`
skips every prompt. From a downloaded archive, no network: unpack it and run
`./install.sh` inside, or `install.sh --from nova-<version>-<os>-<arch>.tar.gz`.
To remove everything it installed, and nothing else:

```sh
bash ~/.local/share/nova/install.sh --uninstall     # add --system or --prefix DIR if you installed with it
```

Windows (64-bit): the `-setup.exe`, or the `.msi` for deployment tools, or the
`.zip` for no installer at all.

**Verify a download** against `SHA256SUMS` (attached below and to the release):

```sh
sha256sum -c SHA256SUMS --ignore-missing
```

```powershell
(Get-FileHash <file> -Algorithm SHA256).Hash -eq ((Select-String "<file>" SHA256SUMS) -split " ")[0]
```

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
