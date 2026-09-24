Seventh beta, and a new name: **NOVA is now YAIF** — *Yet Another Image Format*, which it is.

"NOVA" could not be found in a search, and `.nova` was already used by other programs. Everything
is renamed: the command is `yaif`, files are `.yaif`, the MIME type is `image/x-yaif`, and the
project lives at [Thibault-Savenkoff/yaif](https://github.com/Thibault-Savenkoff/yaif) (the old
links redirect).

Still a **beta**: `.yaif` files written by this build are not guaranteed to be readable by v2.0.0
final, and **v1 and v2 files are not compatible** either way.

## What changed

- **`.nova` files are not read any more.** The coding inside is the same, but the file signature
  changed, and YAIF refuses the old one. Convert them **before** upgrading, with the old `nova`:

  ```sh
  nova decode photo.nova photo.png      # then: yaif encode photo.png
  ```

- **Installing YAIF removes NOVA** — the old command, its viewer plugins and completions — with
  NOVA's own uninstaller: `install.sh` on Linux and macOS removes a NOVA it installed; on Windows
  the `-setup.exe` removes a NOVA installed by the old `-setup.exe`, and the `.msi` one installed by
  the old `.msi` (installed the other way, uninstall NOVA from Settings > Apps first). The `.msi`
  now also replaces an earlier `.msi` instead of installing next to it.
- **Environment variables** are renamed the same way: `NOVA_THREADS` is `YAIF_THREADS`,
  `NOVA_NO_UPDATE_CHECK` is `YAIF_NO_UPDATE_CHECK`.
- **A new logo and icon.**

Nothing else changed in the codec: same sizes, same pixels, same speed.

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
