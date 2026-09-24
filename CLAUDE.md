## Current state

_Updated 2026-09-24._

### To do (details in the entries below)
Next up, in order:
1. **Mac test on real hardware** (user has no Mac access right now): `install.sh`, `nova convert`
   (HEIC -> JPEG/AVIF/HEIC, CR3 -> DNG), `.heic` with its gain map -- CI covers macOS, no human has.
2. **Release `v2.0.0-beta.6`**, first with the trimmed page: check 7 assets (Linux x86_64/arm64,
   macOS universal, setup.exe, .msi, .zip, SHA256SUMS), the collapsed checksum block in the body,
   and that `install.sh` on a Mac downloads the universal archive. Write
   `release/NOTES-v2.0.0-beta.6.md` first; its "Verify" line must point at `SHA256SUMS`
   (`sha256sum -c SHA256SUMS --ignore-missing`), not per-file `.sha256`.
3. **Dolphin duplicate fix** (`d7a015c`, redone after a failed real try): only stub-tested -- confirm on the user's KDE machine
   after a reinstall that one "NOVA" entry is left.
Open, no date:
- `install.ps1` for Windows (`irm | iex`): sidesteps SmartScreen/Defender; ~150-200 lines.
- Code signing on Windows: SignPath Foundation first (free for open source).
- macOS Finder/Quick Look: an ImageIO plugin, deferred past v2.
- GNOME: re-verify the glycin install fix on the VM; Nautilus thumbnails still fail (not chased);
  `plugins/gdk-pixbuf` untested.
- libheif PR #1503: once in a libheif release, drop `libheif-gainmap/` for the system libheif.
- Update check: Windows/WebAssembly branches never run.
- v2.0.0 final: v2 to `main` (the web page still runs v1 until then).
Not planned: Windows on ARM, `lisaac -split`, PowerShell completion filtered by extension.

### Decisions
- Removed `encode_jpeg_retry` from `nova.li`: it re-lowered quality (down to 60) whenever a JPEG-
  sourced `.nova` exceeded 85% of the source JPEG's size. User's call: chasing a size target against
  a competing format isn't a real quality decision and biases the codec toward worse images -- the
  encoder should only adapt to the image's own content, not to beating another file. Kept the
  `50 + Q/2` JPEG-quality-matching rule (that one *is* content-adaptive: it reads the source JPEG's
  own quality, not its size). `MANUAL.md`'s "A grainy JPEG" paragraph removed to match.
- Follow-up adaptive-mode audit (user asked for "better in every respect"): the core heuristics
  (65% photo/graphics split, 3% level-1 hurdle, 10% wavelet-savings hurdle, `50 + Q/2`) are
  well-calibrated and safe-by-construction (uncertain cases fall back to lossless/exact, never to
  more loss) -- deliberately left untouched, no new signals/knobs added for unproven edge cases.
  Fixed two real inconsistencies instead: (1) `put_gain_map` was encoding the HDR gain map at
  `opt_q` instead of `e` (the quality actually chosen for the main image after JPEG-matching) --
  two chunks of the same file answering the same adaptive question differently; now both use `e`.
  (2) `encode_frames`' wavelet-vs-lossless 10% trial called `pick_level` twice (same args, same
  answer) on the "ends up lossless" path -- deduped into one call via a new `lossless_lv` local.
  `test/unit.sh`: 2768/0 failed after each change.
- Distribution plan for v2 (6 steps), **all done**: `nova --version` (`26cd6b9`), `install.sh` +
  `release/pack.sh` (`a932e96`), `build.sh` (`111e811`), GitHub Actions release job (`183d32e`,
  verified green), daily quiet update check (`c424a79`), README (`c32f58d`). **The public
  `v2.0.0-beta` pre-release is out: tag pushed by the user on 2026-09-20** after reviewing the
  notes (Claude Code's auto-mode classifier refuses a tag push as a public surface, so the user ran
  it). **Release notes written and approved by the user (`3899d0a`)**:
  `release/NOTES-v2.0.0-beta.md`. The publish step used `--generate-notes`, which would have made
  the body out of hundreds of raw commit lines with no framing -- it now prefers
  `release/NOTES-<tag>.md` when present and falls back to `--generate-notes` for later patch
  releases. Everything else is ready: `nova.li` already reads `2.0.0-beta` so the tag/version guard
  passes, and `*beta*` sets `--prerelease` on its own. The `--notes-file` path had never run before
  this tag (the publish job is gated on a `v2.*` ref, so `workflow_dispatch` skips it) -- confirmed
  correct by the user on the live page: the release body is the hand-written file, not a commit dump.
- **Windows artifacts now built in CI (`8aa271d`), not yet run.** The beta shipped Linux and macOS
  binaries only; the README asked a Windows user to run `win/dist.sh`, which means installing MinGW
  and NSIS on a Linux box first -- and it left the real-Windows re-test with nothing to install. New
  `windows` job in `release.yml`: it cross-compiles from the `nova.c` the Linux job already writes
  (uploaded as the `c-source` artifact), so Lisaac Ω is not built twice, and runs in a
  `fedora:latest` container because `win/dist.sh` reads MinGW's Fedora sysroot and needs
  `mingw64-zlib`/`mingw64-libwebp`, which Debian and Ubuntu do not package at all. `publish` waits
  on it and now downloads only `nova-*`, so `c-source` stays an input instead of being attached to
  the release. **Verify with `workflow_dispatch` before the next tag** (it runs `build` + `windows`
  and skips `publish`) -- **done, green** (run `35514505701`, `windows` job 59s): both worries were
  unfounded, `fedora:latest` packages `mingw32-nsis`/`msitools` under those names and
  `actions/checkout` is fine in the container after the `dnf install`. Artifact contents verified
  here: `nova-setup.exe` 1.5 MB, `nova-setup.msi` 2.5 MB, `nova-windows.zip` 1.5 MB holding
  `nova.exe`, `nova_wic.dll`, the zlib/libwebp DLLs, the three sample `.nova`, the `.bat` pair and
  the fixed `nova.ps1`. Not yet attached to the published `v2.0.0-beta` release -- that needs a
  `gh release upload`, ask the user first.
  Note for triggering it again: the repo's default branch is `main` (still v1), whose `release.yml`
  has no `workflow_dispatch`, so GitHub shows no "Run workflow" button for the v2 one. The web UI
  reads that button off the default branch only; the API does not care, so
  `gh workflow run release.yml --ref v2 -R Thibault-Savenkoff/nova` works. For the same reason runs
  are labelled "Build & Release" (main's `name:`) even though the file executed is v2's.
- **`v2.0.0-beta.2` is PUBLISHED (2026-09-21)** -- the first nova release with Windows binaries,
  and the first where RAW works there. Nine assets: Linux x86_64, macOS arm64 and x86_64 (each with
  its `.sha256`), plus `nova-setup.exe`, `nova-setup.msi` and `nova-windows.zip`. Why a second beta
  rather than `gh release upload` onto the first: the Windows artifacts are built from HEAD, which by then was 19 commits past
  `v2.0.0-beta`, so attaching them there would ship Windows binaries that do not match the tag
  while the Linux/macOS ones do. Nothing changed in the codec or the format between the two.
  **How it was tagged, worth remembering**: the user's Windows machine has no clone of the repo and
  no `gh`, so the tag was made from the web UI's "Draft a new release" form (Choose a tag -> Create
  new tag on publish, Target `v2`) -- the only browser-only way to create a tag. That form also
  creates the release, which used to make the job die on "release already exists", so
  `release.yml`'s publish step now edits and uploads when the release is there and creates it
  otherwise (`8adf240`); `--generate-notes` stays on the create path only, `gh release edit` has no
  equivalent. Verified on this run: the empty title and body the form left were overwritten by the
  hand-written notes, and all nine assets attached.
- **An `install.ps1` for Windows is worth doing, not started.** Same shape as the Linux one
  (`irm ... | iex`), and its real value is that a script sidesteps both SmartScreen and the
  `Wacatac.C!ml` false positive that hits the unsigned NSIS installer -- the only free workaround
  until the binaries are signed. It also runs in memory, so the execution policy does not block it.
  Cost: it has to redo what NSIS already does (PATH, the Settings > Apps entry, clean uninstall,
  `.sha256` check), about 150-200 lines, and it becomes a third Windows install path to keep in
  step with `nova.nsi` and `nova.wxs`. `regsvr32` still needs elevation whatever happens.
- `win/nova.nsi` rewritten around NSIS's `MultiUser.nsh` + `MUI2.nsh`: a wizard page lets the user
  pick per-machine (HKLM, elevation) or per-user (HKCU) install, license page, `ManifestDPIAware
  true` (was blurry at non-100% Windows scaling). `win/nova.wxs` (MSI) is still per-machine only.
  Both build-tested here (`makensis`, `wixl`) -- not run on real Windows since these fixes.
- `install.sh` is quiet by default (`run()` only prints `$ cmd` on failure); `--verbose` restores
  full command tracing. Paths in messages go through the existing `pretty()` ($HOME -> `~`). This
  undoes a verbosity choice from a prior session that was about *my* caution in that session's chat,
  not a real user requirement for the script's own output.
- Shell completion: `completions/nova.bash` and `.fish` added, installed by `install.sh` into
  standard auto-load dirs (`share/bash-completion/completions/`, `share/fish/vendor_completions.d/`)
  -- no rc-file edit needed, unlike zsh's `fpath`. `completions/nova.ps1`
  (`Register-ArgumentCompleter`) ships in the Windows zip/NSIS/MSI instead (`win/dist.sh`/`.nsi`/
  `.wxs`), since `install.sh` never runs on Windows; both Windows installers wire it into
  `$PROFILE` themselves (see the PowerShell-completion entry below). cmd.exe has no
  hook for a third-party program's argument completion -- nothing shipped for it.
- Icon quality: stale note, checked and closed. `win/nova.ico` (`0d9eef0`) is already multi-resolution
  (256/64/48/32/24/16 px) and legible down to 16 px -- no further work needed.
- Missing system deps (cmake, Qt-devel, libheif...) are never auto-installed by install.sh/build.sh
  -- detected and skipped with a printed command to copy-paste. Deliberate: auto-installing across
  distros needs sudo and can break a system.
- **`release/pack.sh` works from GitHub's "Source code" archive too (`be83fa2`).** It listed files
  with `git ls-files`, which fails into an empty pipe without a `.git`, and still exited 0 -- so
  `build.sh` from that archive installed `bin/nova` alone (no install.sh, completions, plugins,
  docs) without a word. Outside a clone it now uses `find` on the same paths; checked both ways,
  27 files each. Found because the user asked what `build.sh` does from the source archive.
- **`install.sh` run from an unpacked release archive installs that archive** (user report,
  2026-09-24: unzipping a CI artifact and running `./install.sh` downloaded the latest release
  instead). When it runs from a file (`BASH_SOURCE`, empty under `curl | bash`) with an executable
  `bin/nova` beside it and no `--version`, `src` is that directory and the version comes from
  `bin/nova --version` (which also fails cleanly for the wrong OS/arch). The glycin `cargo build`
  now uses `--target-dir "$tmp/glycin"` so nothing is written into the user's unpacked folder.
  `test/install.sh` case 5b checks it with the release URLs pointed at a dead port.
  Same report: the closing "Uninstall:" hint was always `curl ... | bash -s -- --uninstall`, and
  without `--prefix`/`--system` even when installed with one. `install_bin` now also installs
  `install.sh` itself to `$prefix/share/nova/install.sh` (in the manifest), and the hint is
  `bash <that> --uninstall [--system | --prefix DIR]` -- offline, and right for the prefix. The script
  deletes itself during uninstall; bash keeps reading from the open fd, verified to finish.
- **`install.sh` finds the latest v2 release through `releases.atom`, not the REST API** (user hit
  `403` + "no v2 release found", 2026-09-24): the API allows 60 unauthenticated requests an hour per
  IP, shared with everything on that network. The feed is plain web, newest first, v1 and v2 mixed
  (filtered on `releases/tag/v2.`). `NOVA_FEED` overrides it for `test/install.sh`. nova's own daily
  update check (`nova_update.li`) still uses the API -- one call a day, fails silently; left alone.
- **`curl | bash` never asked anything** (user report, 2026-09-24): `ask()` tested `[ -t 0 ]`, and
  piped, stdin is the script -- so every prompt (zshrc lines, all viewer plugins) answered "no"
  even in a real terminal. It now reads the answer from `/dev/tty` when stdin is not one (the
  `rustup`/Homebrew way), and says no only when there is no terminal at all (CI, Docker: opening
  `/dev/tty` fails there, tested with `{ : </dev/tty; }`). Verified through `script` (a pty) with
  `cat install.sh | bash -s`. Same report: the SHA256SUMS lookup printed `curl: (22) ... 404` on
  beta.5 (which has none) before falling back to `.sha256` -- `-S` dropped from that fetch.
- **Dolphin listed NOVA twice in its preview menu** (user report, 2026-09-24: `Image NOVA` and
  `Images "NOVA"`): recent Dolphin/kio-extras also reads freedesktop `.thumbnailer` files, so the
  gdk-pixbuf plugin's `/usr/share/thumbnailers/nova.thumbnailer` (built whenever gdk-pixbuf-2.0 is
  present, i.e. on most KDE systems too) showed next to `libnovathumb.so`. `install.sh` now skips
  that file when the KDE thumbnailer was installed in the same run (`kde_thumb`), and removes it if
  it is byte-identical to ours. Kept the KDE plugin: it decodes in-process, no process per thumbnail.
  Tested with stub pkg-config/cmake/cc (no Qt/KF6 here), both ways. **First real try failed**: the
  removal lived in `make_gdk_pixbuf_plugin`, so it only ran when the user ALSO said yes to the
  gdk-pixbuf loader -- they said no, the file stayed. Now `drop_pixbuf_thumbnailer` runs right after
  the KDE plugin installs (stub-tested: KDE y, gdk-pixbuf n -> removed). Re-check on the real machine.
  **Second real try: "KF6KIO not found, Dolphin thumbnailer skipped"** on the user's Fedora KDE, which
  has it: `install.sh` detected KIO with `pkg-config --exists KF6KIO`, and KDE Frameworks 6 ship only
  CMake package files, no `.pc` -- so install.sh had NEVER built the Dolphin thumbnailer; the user's
  `libnovathumb.so` came from the manual cmake build. `has_kf6kio` now looks for
  `KF6KIO/KF6KIOConfig.cmake` under the usual `lib*/cmake` dirs (checked both ways here).
- `install.sh --uninstall` is manifest-only: every file/rc-line it writes is recorded in
  `$prefix/share/nova/installed.txt`; uninstall only `rm -f`s a single path read back from it --
  never a directory, never a computed path. Deliberate (see Traps).
- `NOVA_TEST_ROOT` redirects root-owned plugin installs into a fake root, so `test/install.sh` never
  needs real sudo.
- Model: user is on Claude Pro. Tell them which /model and /effort to set before each significant
  task. Opus 5 `high` cost only 4-10% of the 5h quota for a hard Lisaac task -- fine to recommend
  again; Sonnet 5 (any effort) otherwise. Opus 5 `low`'s cost is unconfirmed -- don't state a number
  until actually measured.

### In flight (not yet committed)
- **Extensions case-insensitive + decode overwrite prompt (`ed72b7b`)**, found while preparing
  beta.3: every `has_suffix` check now goes through `as_lower` (an uppercase output like `OUT.PNG`
  failed with "unsupported output extension"), `decode`/`preview` call `keep_or_rename` like
  `encode`, and `free_name` keeps the destination's own extension (`OUT.PNG` -> `OUT-1.PNG`; it
  used to strip 5 chars and append `.nova`). `test/unit.sh` all OK (uv fuzz skipped: no `uv` here).
  Convention: nova *writes* lowercase `.nova`, accepts any case. `nova.li` already reads
  `2.0.0-beta.3`. **`v2.0.0-beta.3` PUBLISHED 2026-09-23** (tag on `1c5c425`, run `35821106467`):
  14 assets (4 Linux/macOS tarballs + 3 Windows, each with `.sha256`), pre-release, notes from
  `release/NOTES-v2.0.0-beta.3.md`.
  Windows re-test for beta.3 done (2026-09-23): HEIC writing opens on the iPhone, TAB completes.
  The `.heic` has no HDR -- documented limit (`MANUAL.md:233`, "libheif cannot write it"); `.avif`
  and `.jpg` carry the gain map. **Checked against libheif 1.23.4's public headers (2026-09-23):
  still no way to write one.** No gain-map/tmap call at all; the generic item API
  (`heif_context_add_item`, `add_item_references`) could create the `tmap` item and its `dimg`
  refs, but there is no call to create the `altr` entity group (tmap + primary) the spec needs,
  none to mark the encoded gain-map image hidden (it would show as a second picture), and none to
  attach properties to a raw item. Only way left: rewrite the HEIF `meta` boxes by hand after
  libheif writes the file (~1 day, fragile). Not worth it: `.avif`/`.jpg` already do this.
  `MANUAL.md:233` stays correct as written.
  Who does write one (searched 2026-09-23): **libheif PR #1503** ("Add support for handling 'tmap'
  items", behind `-DWITH_EXPERIMENTAL_GAIN_MAP=1`) -- **still OPEN, unmerged** since 2025-04;
  a fork keeps it rebased on 1.23.1, and **libultrahdr v2.0.0 already builds on it** (so it does
  write HEIC gain maps, from a patched libheif). Apple's own ImageIO (macOS 15/iOS 18) writes them
  natively -- macOS only. (First decision "wait for #1503" superseded below.) **When #1503 lands in
  a libheif release, drop `libheif-gainmap/` and load the system libheif instead** -- re-check the PR
  before any HEIC work.
  Follow-ups the same day: libultrahdr v2 is no way around it (it embeds the same PR, pinned to an
  old libheif commit). **User's call: build the patched libheif ourselves, on every platform, at
  install time, with an opt-out -- and (my adjustment, user agreed) used for WRITING HEIC ONLY**:
  reads stay on the system libheif, which gets distro security fixes; our copy would not.
  **Built (`e8540bd`), CI green (runs `35832817235`, `35871161177`). CONFIRMED ON REAL HARDWARE
  (2026-09-24): Windows installer -> `nova decode test.nova hdr.heic` -> `tmap` check True, and the
  iPhone shows the HDR exactly as it does the AVIF.** macOS covered by CI instead of the user's Mac
  (run `35957900338`): every Linux/macOS build job now runs `install.sh --from` the packed archive
  (so it builds libnova-heif), writes `docs/samples/photo.nova` to `.heic` and fails without a
  `tmap` -- green on all four, macOS arm64 and x86_64 included (Apple clang, the
  `_NSGetExecutablePath` lookup). It even works where the system has no libheif at all (the macOS
  runners have none): libnova-heif does the whole write. **Release: `v2.0.0-beta.4` prepared
  (`nova.li` bumped, `release/NOTES-v2.0.0-beta.4.md`, `dd71ad6`/`bdd9f27`). PUBLISHED
  (tag on `bdd9f27`, run `35958881890`): 14 assets, pre-release, notes with the explicit #1503 link.** Trap: a bare `#1503` in release notes is autolinked by
  GitHub to *this* repo's issue #1503 -- always write `owner/repo#N` with an explicit URL.
  **Release `v2.0.0-beta.5` (2026-09-24)**: `nova.li` bumped,
  `release/NOTES-v2.0.0-beta.5.md` (nova convert + timings, install.sh fixes, Dolphin duplicate,
  Done time). **PUBLISHED 2026-09-24** (tag on `6a6b9ae`, run `35980687040`, all green incl. the
  Intel-Mac HEIC test): 14 assets, pre-release, body = the hand-written notes.
  **Release page trimmed (user, 2026-09-24: "trop de trucs, on s'y perd"): 14 assets -> 7.**
  (1) No more per-file `.sha256` (`pack.sh`, `win/dist.sh` stopped writing them): `publish` writes one
  `SHA256SUMS` and appends it to the notes as a collapsed `<details>` block (on the edit path without
  a NOTES file it keeps the web form's body, minus an earlier block). `install.sh` reads SHA256SUMS,
  falls back to `<archive>.sha256` for releases up to beta.5. GitHub also shows each asset's sha256
  itself now. (2) **macOS universal binary**: both Mac build jobs stay (the Intel one is still the
  only Apple-clang build of kvazaar's x86 asm, HEIC test on tags); their artifacts are now
  `part-macos-<arch>`, and a `macos-universal` job `lipo`s them, packs
  `nova-<v>-macos-universal.tar.gz` and installs it with `--from`. `install.sh` on macOS asks for the
  universal archive (1-byte range GET) and falls back to per-arch for older releases; `unpack` uses
  the archive's own name, `--from` accepts `-universal`. (3) **`.msi` kept**: the user installs
  nearly everything with MSIs. **CI green (run `36003142179`)**: universal archive 612 KB (arm64 315 +
  x86_64 370), installed with `--from` on the arm runner. First release to show it: beta.6.
  **beta.5 on real Windows (2026-09-24)**: `nova convert IMG_1152.HEIC test.jpg` (12 Mpx iPhone HEIC)
  said 11.3 s the first time, then 0.6 s on every run, with or without `NOVA_THREADS=1` -- the first
  launch of a freshly installed unsigned `nova.exe` + DLLs is scanned by Defender. Not a nova bug;
  if a user reports a slow first run, that is why. HEIC -> PNG: 3.9 s (lossless deflate of 12 Mpx),
  not chased.
  **Workflow review: done (`f479a0c`).** `release.yml` now runs on every push to `v2` (not
  `**.md`-only pushes; `paths-ignore` is ignored for tags, so a release always runs), with
  `concurrency` cancelling a superseded branch run (never a tag run); `test/unit.sh` (uv via
  `astral-sh/setup-uv`) + `test/install.sh` run in the Linux x86_64 job -- they never ran in CI,
  which is how `test/install.sh` stayed broken since beta.3; `permissions: contents: read`, `write`
  on `publish` only; `fedora:44` pinned and in the windeps cache key (kept Fedora: only distro
  packaging the mingw64 zlib/libwebp/LibRaw/lcms nova ships); the HEIC install test skipped on
  `macos-15-intel` except on tags (it alone builds kvazaar's x86 asm with Apple clang). Run
  `35961072361`: tests green (unit all OK, 720 corrupt files, install ALL OK), Intel Mac 382 -> 32 s.
  Run `35961563294` (the convert commit): all green, first Windows job on `fedora:44` (520 s: new
  cache key, deps rebuilt once; later runs hit the cache).
  `test/unit.sh` now FAILs when `uv` is missing instead of silently skipping the fuzz -- expected
  locally here (no uv), not a regression.
  **`nova convert <src> <dst> [decode options]` (`1c53d31`)**, user's request after beta.4: any
  source `encode` reads -> any output `decode` writes, no `.nova` left behind. **Direct path since
  the follow-up (user asked, 2026-09-24)**: non-RAW sources skip the codec -- `load_sources`, then
  `put_source_meta` into `Nova_codec.out`, whose MDAT chunks (plus the gain map's ISO metadata
  appended) become `data` with `meta_pos`/`meta_len` filled by a chunk walk; `gm*` from `Nova_heic`;
  then `write_image` directly. 7.7 Mpx JPEG->PNG 3.4 -> 0.7 s, ->JPEG 3.1 -> 0.5 s. **Byte-identical
  to `encode -m lossless -l 1` + `decode`** for jpg/png(alpha)/png(text)/avif+tmap/heic+tmap sources
  x png/jpg/tif/webp/avif/heic outputs (lossy ones compared with `decode -m lossy`); tmap kept in
  AVIF/HEIC, hdrgm in JPEG. RAW sources still go through a `.nova` **held in memory** (`in_memory`
  slot, `read_nova` skips `load_file`) for its dispatch (DNG/PGM/develop) -- but **without coding the
  sensor frame** (user report: `convert X.CR3 X.dng` still printed both steps, 14.9 s): `convert_to`
  set -> `encode_raw` writes an empty FDAT and skips the LibRaw half-size preview unless the output
  is `.dng` (it is only the DNG thumbnail); `read_nova` accepts an empty FDAT only when `in_memory`
  (samples already in `Nova_raw`) and skips its IHDR line. 250D CR3 (raw.pixls.us sample): DNG
  14.5 -> 1.4 s, PNG 20.1 -> 6.3, TIFF 19.1 -> 5.5, PGM 18.4 -> 0.6, all byte-identical to the old
  path; `nova encode` of the CR3 unchanged. In memory, not a temp file, because on Windows only
  nova_par's replica 0 writes files. User's real run then said "6.0 s": the replace prompt's
  wait was counted (t0 set in main) -- `keep_or_rename` now resets `t0` after the answer (all its
  call sites run before any work). **Confirmed on the user's machine: `convert IMG_1398.CR3 test.dng`
  "in 1.2 s" (was 14.9 s).** Local RAW testing: LibRaw 0.22.1 built into scratchpad `lr/`
  (`LD_LIBRARY_PATH`), Debian only has 0.21 (so.23). Lisaac trap met: a one-line
  block `{ i:Int Nova_codec.put_byte ... }` is a SYNTAX error ("Added '}'" warning, error at a later
  `}`) -- an uppercase prototype right after `i:Int` is read as part of the type; newline after it.
  Local test libs: `apt-get install libwebp7 libheif1 libheif-plugin-{libde265,kvazaar,aomdec,aomenc}
  libavif16` (Debian trixie); libnova-heif found via a copy of nova in scratchpad `pfx/bin/`. Without `-m`, WebP/AVIF/HEIC output is
  lossless for PNG/TIFF/PAM sources, lossy otherwise. Refuses a `.nova` on either side (points to
  encode/decode). Completions (4 shells) + MANUAL "Converting" + README updated.
  Previously:
  `libheif-gainmap/build.sh` = libheif 1.23.4 + `pr1503.patch` (fxthomas rebase re-diffed for 1.23.4,
  one fix: `get_unused_item_id()` returns `Result<>` since 1.23.2) + kvazaar static, all other
  codecs off, tarballs SHA-256-pinned, output renamed **libnova-heif** (distinct file name *and*
  soname, so glibc/dyld/Windows can never hand it out for the system libheif or vice versa).
  `install.sh` step `install_heic_hdr` (after `check_libs`): installs `$prefix/lib/nova/libnova-heif.
  {so,dylib}` + a `.stamp` (cksum of recipe; unchanged recipe = no rebuild), skips with the distro
  command when cmake/cc/c++/patch are missing, `--no-heic-hdr` opts out; test/install.sh passes it.
  `win/deps.sh` runs the same recipe with `CMAKE=mingw64-cmake` -> `libnova-heif.dll` (marker =
  recipe cksum; CI cache key now hashes `libheif-gainmap/*`); in `dist.sh`, `nova.wxs`, README.txt
  (LGPL: modified libheif, source = `libheif-gainmap/`). nova side: `ng_export` in `nova_heic.li`
  (own `ng_*` pointers, never mixed with the `nh_*` system ones), looked up at
  `<exe dir>/../lib/nova/` (Linux `/proc/self/exe`, macOS `_NSGetExecutablePath`), next to
  `nova.exe` on Windows; returns -1 when absent -> plain HEIC as before. Lossy + `hdr_ok` only.
  Traps: (1) **`cmake --build --parallel` with no count = unbounded `make -j`**: it OOM'd the whole
  8 GB host (killed the session and most containers) -- always pass a count; `install.sh`'s Qt/KDE
  plugin build had the same bug, fixed. Locally, build under `ulimit -v 2500000` and `JOBS=2`.
  (2) #1503's *reader* derefs the tmap's `colr` unchecked, so nova always writes one (same
  primaries, linear transfer). (3) kvazaar static on Windows needs `KVZ_STATIC_LIB` (else
  dllimport); set on the heif target -- untested until the CI run. (4) `pack.sh` packs only
  git-tracked files: new dirs must be `git add`ed before `build.sh` can ship them.
  Also fixed: `test/install.sh` hard-coded `v2.0.0-beta` and had failed since the beta.3 bump.
- **Windows on ARM: not planned, decided 2026-09-23.** x64 `nova.exe` already runs there under
  Windows 11's emulation; only Explorer thumbnails would fail (ARM64 Explorer won't load an x64
  `nova_wic.dll`). Cost ~1-2 days: Fedora has no aarch64 MinGW (needs llvm-mingw), its mingw64
  packages (zlib, libwebp, LibRaw, lcms) are x86_64 only so everything is rebuilt, wixl likely has
  no ARM64 MSI, and no ARM Windows machine to test on. Revisit only if someone asks.
- User ran a full manual test pass (`~/test_nova/Tests.md`, 29 items) on real files outside the
  sandbox. Found two real bugs, both fixed in the working tree here, not yet committed:
  1. **Animation with JPEG sources: every decoded frame was the last frame's image**, not each
     frame's own content (`nova encode a.jpg b.jpg c.jpg out.nova` then decode gave 3x the same
     picture). Root cause: `load_sources` (nova.li) stored the `C_array` that `Image.load` returns
     as-is; the JPEG coder (`Img_jpg` in Lisaac's `lib/draw/img/img_jpg.li`, a stb_image port) is a
     shared singleton instance that reuses one output buffer across loads, so all frames ended up
     aliasing the same memory. PNG doesn't hit this (its coder allocates fresh memory per load) --
     that's why the bug was JPEG-specific. Fixed by copying the buffer into a fresh `C_array`
     (mirroring the copy the HEIC branch already did two lines above) right in `load_sources`, the
     one place all non-HEIC frame sources go through. Verified with 3 solid-colour JPEGs: fixed
     output decodes to 3 distinct frames; `test/unit.sh` still 2768/0 failed after the fix.
  2. **`nova bench` couldn't read RAW files** (`cannot read image X.CR3`) while `nova encode` reads
     the same file fine. Cause: the `bench` command dispatch never had the `is_raw` check that
     `encode`'s dispatch has (nova.li ~1751) before calling `load_sources`/`encode_frames` --
     `bench` always took the non-RAW path. Fixed by adding the same `is_raw` -> `encode_raw` branch
     to `bench`'s loop. Both animation and bench fixes are committed (see below) -- confirmed by the
     user on real files: bench+CR3 "c'est bon", animation "3 frames différentes exportées".
  3. **DNG output had no embedded thumbnail** -- fixed and committed separately (`8ceb5ce`), see
     its own entry below.
- **DNG thumbnail: done and committed (`8ceb5ce`).** `write_dng`/`Nova_tiff.finish` embed the RAW's
  PREV-chunk preview (LibRaw half-size development) as a JPEG thumbnail, referenced from IFD0 via a
  `SubIFDs` (tag 330) entry -- not the classic Exif IFD0->IFD1 next-pointer chain, which is for plain
  Exif JPEGs and which DNG readers don't follow for previews. Two earlier attempts (a `start`-vs-
  `set_thumb` ordering bug, then a wrong guess that a missing `BitsPerSample` tag was the blocker)
  didn't work; a byte-level diagnostic (parsing IFD0's next-IFD offset and IFD1 by hand in Python) is
  what found the real cause. Confirmed both via a direct `libraw_unpack_thumb()` test (correct
  tformat/width/height/length) and visually in Gwenview. **Still black in Dolphin** -- isolated to
  Dolphin's own `rawthumbnail.so` (kdegraphics-thumbnailers) failing to show a thumbnail that LibRaw
  itself reads correctly; "RAW images" preview is enabled in Dolphin's settings and the thumbnail
  cache was cleared, so this isn't a nova-side bug or an easy config fix. Closed on nova's side.
  Useful for future TIFF/IFD work: `finish`'s IFD1 code path is shared by `write_image`'s TIFF output
  (mode 1), so it can be exercised locally against `test/corpus/*.png` alone, no CR3/LibRaw needed.
- **DNG "darker than the .nova": confirmed non-bug (2026-09-21).** The `.nova` preview (`PREV`) is
  LibRaw's development with `no_auto_bright = 1` and linear gamma, *plus* nova's own tone curve
  (`nova_look.h`, `nova_rawin.li:182`) -- a finished-looking photo. A DNG carries sensor data and
  colorimetry only, so whoever opens it decides the brightness: comparing the two is not
  apples to apples. The test that settles it is the DNG against the **original CR3 in the same
  viewer**, and the user confirmed they match. So nova's DNG is faithful to its source, which is
  the target. **Do not add `BaselineExposure` (tag 50730)** for this: nova omits it, real camera
  DNGs carry it, but adding it would render nova's DNG *brighter than the CR3 it came from*.
- `nova decode raw.nova out.pgm` "looks black" -- confirmed non-bug. User checked pixel extrema
  (`1943, 16383`): real sensor data, not black; just a naive linear view of unprocessed raw values
  (expected, per MANUAL.md -- the bare sensor frame has no demosaic/white-balance/gamma). Closed.
- Gwenview crash opening an animated `.nova` (JPEG sources): reported once, alongside the animation
  JPEG-aliasing bug (both frames-related). No longer reproduces after that fix was committed
  (`9f69c34`) -- likely the same root cause (all frames aliasing one shared buffer destabilized the
  Qt plugin). Closed, no separate fix made; re-open if it recurs.
- **HDR gain map (#18): closed, not a bug.** A structural dump (MPF segment + both JPEGs' `hdrgm:`
  XMP gain-map description) of a real Ultra HDR JPEG confirmed everything spec-correct: valid MPF
  linking the SDR and gain-map images, complete `hdrgm:` fields (GainMapMin/Max, Gamma, Offsets,
  HDRCapacityMin/Max) on the gain-map image. Confirmed rendering correctly on the user's iPhone.
  Gwenview/darktable showing "pas terrible"/the plain SDR image is expected: neither supports Ultra
  HDR gain maps (a 2023 format, mainly Android/Chrome so far) -- not evidence of a nova bug.
- **HDR `-hdr` rendering differences (#17): closed, not a bug.** `nova decode x.nova out.{png,avif,
  heic,tif} -hdr` gave visibly different-looking results per format (PNG flat/no contrast, TIFF
  over-contrasted, AVIF over-exposed, HEIC different from source) -- exactly the documented,
  by-design behavior: `-hdr` writes raw PQ (PNG/AVIF/HEIC) or linear (TIFF) values meant for an
  HDR-aware editor/player, not a plain viewer (MANUAL.md's HDR section already says as much). The
  non-`-hdr` Ultra HDR JPEG/AVIF (the one meant for normal viewing) was confirmed to look correct
  and identical across viewers, including on the user's iPhone.
- Real bug found earlier (real Windows test) and fixed: decoding to an unrecognized extension (e.g.
  `nova decode x.nova x.cr3`) silently wrote a PNG under that name instead of failing --
  `write_image` (nova.li) had no `else { fail }`. Fixed, verified (round-trip + `test/unit.sh`:
  2768 tests / 0 failed).
- Test 1 (Windows install/uninstall) done once for real: binary/completion/mime/uninstall all pass;
  found and fixed the CR3 bug, name casing, and the NSIS issues above. Not yet re-tested on real
  Windows since. The user's `~/test_nova/Tests.md` pass above covers most of tests 2-5's ground
  (encode/decode/metadata/bench/RAW on real files) though not run through IrfanView/GIMP specifically.
- **fish completion: tested and fixed (`f7a4279`).** Installed fish here, verified non-interactively
  with `complete -C'nova ...'` (no real shell needed). Found and fixed a real bug: `nova <TAB>` at
  the top level showed the 6 subcommands mixed in with every file in the current directory, because
  fish falls back to default file completion unless a rule opts out with `-f`. All other paths
  (`-m`, `-l`, `-look`, positional file args) checked correct.
- **PowerShell completion: tested and fixed (`766bfec`).** `pwsh` 7.6.6 turned out to be installed
  here after all (CLAUDE.md previously said it wasn't), so it was verified non-interactively via
  `TabExpansion2 -inputScript ... -cursorColumn` -- no real shell or Windows box needed. Found one
  real bug with three symptoms: `$prev = $tokens[-2]` and `$tokens.Count -le 2` assumed the word
  being completed is already a `CommandElement`, which after a trailing space it is not, so every
  index was off by one -- `nova encode -m <TAB>` listed files instead of `adaptive lossless lossy`
  (same for `-l`, `-look`), and `nova encode <TAB>`/`nova bench <TAB>` re-offered the subcommand
  list instead of files. Fixed with an explicit `$pos`. 15 cases checked, all correct.
  Known gap, deliberately not built: unlike `nova.bash`/`.fish`, the ps1 does not filter file
  completion by extension (`.nova` for `preview`/`info`, images for `bench`, `.mov` for `-live`) --
  it offers every file. Cosmetic, add only if it grates in real use.
  Inherent PowerShell limit, not a nova bug and nothing to fix: `Register-ArgumentCompleter -Native`
  matches the command name as typed, so `nova` and `nova.exe` both complete but a path-qualified
  `.\nova.exe` does not (it falls back to listing files). Checked here with `TabExpansion2`. It only
  bites when running from an unzipped folder that is not on PATH; the installer puts `nova` on PATH,
  so the normal case is fine. Sourcing `nova.ps1` from `$PROFILE` is still manual either way.
- **Real-Windows re-test: DONE and green (user's machine, 2026-09-20/21)**, using the CI-built
  artifacts. Final pass over the installer route: RAW encode of a real CR3, `nova decode` back,
  tab completion in a fresh terminal (the installer's opt-in component), Explorer thumbnails on the
  bundled samples, double-click into Windows Photo Viewer, and uninstall (PATH entry and the
  `$PROFILE` line both gone). `.nova` shows black *inside the Photos app* -- expected and already
  documented, Photos takes no third-party WIC codec; the Explorer thumbnail is correct.
  Five real bugs came out of it, all fixed and re-verified on the machine:
  1. `nova-setup.exe` is blocked twice by Windows: SmartScreen ("Éditeur inconnu", unsigned) and
     then Defender itself with `Trojan:Win32/Wacatac.C!ml`. The `!ml` suffix is a machine-learning
     heuristic and this is the classic false positive for an unsigned MinGW-built NSIS installer --
     **submitted to Microsoft by the user (done, noted 2026-09-22)**; a verdict only covers the
     file hash it was made on, so each new build (beta.3 included) can be flagged afresh -- (microsoft.com/wdsi/filesubmission, as **Software developer**, not
     Home customer: that path is for the software's own author and is not deprioritised). Until the
     binary is signed this recurs on every build, because SmartScreen reputation for an unsigned
     file is tied to the file hash. See the code-signing note above.
  2. **Camera RAW did not work on Windows at all** (`nova encode IMG.CR3` -> "libraw not found"),
     although RAW is a headline v2 feature: `win/dist.sh` shipped only zlib and libwebp, and nothing
     said so. **Fixed and verified in CI**: Fedora packages `mingw64-LibRaw` 0.22.1, exactly the
     version `nova_rawin.li` pins, and its DLL is `libraw_r-25.dll` -- which `win/nova_win.h`'s
     `dlopen` shim already derives from `"libraw_r.so.25"`, so no code changed. Its dependency
     closure (walked with `objdump -p` in a throwaway CI branch rather than guessed) adds
     `libgcc_s_seh-1`, `liblcms2-2` and `libstdc++-6`. Also found: Fedora's MinGW DLLs are
     unstripped, `libstdc++-6.dll` alone was 29.7 MB -- `dist.sh` now strips them, so the installer
     went 8.6 MB -> 2.65 MB and the zip 11.4 MB -> 3.1 MB (about +1.1 MB over the pre-LibRaw build).
     `nova.nsi` globs `*.dll` now so a new DLL cannot miss the installer; `nova.wxs` cannot glob and
     pins `libraw_r-25.dll` by name, which fails loudly at `wixl` time on a LibRaw major bump --
     acceptable because such a bump needs a `nova_rawin.li` change anyway.
     **HEIC and AVIF stay unavailable on Windows**: Fedora has no MinGW build of libheif or libavif.
     Said in the zip's README.txt and in README.md now. **Phase 1 is DONE: Windows reads HEIC**
     (`win/deps.sh`). Plan:
     cross-compile the chain from source in the CI job, cached the way Lisaac Ω already is, rather
     than lifting MSYS2's prebuilt DLLs (the user chose this directly: MSYS2's `mingw64` repo would
     work, but its `ucrt64` one links a different C runtime, and mixing runtimes for a dlopen'd
     library crashes the moment an allocation crosses the boundary). A probe against
     `fedora:latest` confirmed **no** mingw64 package exists for libheif, libde265, x265, kvazaar,
     aom, dav1d, rav1e, svt-av1 or libavif -- only jpeg, lcms and openjpeg -- so everything has to
     be built. Note it is two libraries, not one: nova uses libheif for HEIC and **libavif** for
     AVIF (`README.md:186`). Phases, each useful on its own: (1) HEIC *reading*, libheif +
     libde265, ~half a day; (2) AVIF, libavif + aom, needs nasm, ~a day, and this is what the HDR
     gain-map output needs; (3) HEIC *writing*, kvazaar, ~2 h. **Use kvazaar (LGPL), not x265
     (GPL)**, for the HEVC encoder: shipping a GPL DLL inside an otherwise-MIT package raises a
     licence question kvazaar avoids. All of it can be iterated from CI, no Windows machine needed.
     **Phase 1 shipped**: `win/deps.sh` builds libheif 1.23.4 (the version Fedora ships natively)
     with libde265 1.1.3, through `mingw64-cmake`, into a staging tree the CI caches on
     `hashFiles('win/deps.sh')` -- the pinned versions and the cmake flags are the only things that
     invalidate it, so a rebuild costs ~2 min once and nothing afterwards. `ENABLE_PLUGIN_LOADING=OFF`
     matters: with it on, libheif looks for its codecs as separate plugin DLLs at run time, which
     would each have to be found and shipped. Both libraries are LGPL; their `COPYING` is staged and
     packaged, and the zip's README.txt names the versions and upstream URLs (what relinking needs).
     Trap this caught: **`nova.wxs` lists its files one by one and `wixl` does not complain about
     what is missing**, so the MSI silently kept shipping without the new DLLs while the zip had
     them -- the MSI going 4.2 MB -> 5.7 MB is how it was confirmed fixed. `nova.nsi` globs `*.dll`
     and was fine. **Verified on the user's real Windows machine (2026-09-22)**:
     `nova encode IMG_1152.HEIC test.nova` reads a 3024x4032 iPhone HEIC and writes the `.nova`
     (88.6 % of the source, q 90, level 5, 6.3 s). The MSI uninstall is clean too since the 2762
     fix. Phase 1 is done end to end.
     **Phase 2 (AVIF) builds green in CI** (run `35754434774`, `windows` job 6m43s including aom
     from scratch). **First real-Windows result (2026-09-22)**: HEIC -> `.nova` -> `.avif` on the
     user's machine, and the AVIF opens natively on their iPhone as AVIF with full EXIF, 3024x4032,
     1.3 MB against 1.6 MB for the source HEIC. **HDR confirmed too: the `tmap` check came back
     True, so libavif wrote the gain map. Phase 2 is done end to end.** Why that check and not the
     file opening: when libavif is missing, `nova.li:527` falls back to a plain AVIF
     without a word, and that opens just the same (a phone screenshot is SDR anyway). The
     discriminating check is the ISO 21496-1 `tmap` item in the file --
     `[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes("x.avif")).Contains("tmap")` in
     PowerShell; if False, `nova info x.nova` printing "... HDR gain map" puts it on libavif,
     otherwise the source simply had no HDR. libheif's own configure summary is the proof that the
     codecs went in rather than being silently skipped -- its `WITH_*` options are wishes, not
     requirements: "libde265 HEVC decoder: + built-in / AOM AV1 decoder: + built-in / AOM AV1
     encoder: + built-in / x265, Kvazaar: - disabled". Read that summary after any change here. One library unlocks all of it: aom
     3.13.1, shared, so libheif and libavif link one copy instead of embedding two. libheif is
     rebuilt with `WITH_AOM_DECODER/ENCODER` (it is what reads and writes a plain `.avif`);
     libavif 1.3.0 is only for the HDR gain-map path (`nova_heic.li` dlopens it for that alone, and
     1.3.0 is the version its struct offsets were checked against -- 1.4.x exists, no reason to
     move). `win/deps.sh` now builds per library behind a marker file, with `restore-keys` on the
     CI cache, so editing libheif's flags no longer rebuilds aom (~9 min on its own).
     **Cost, measured: the zip goes 3.1 -> 8.0 MB and `nova-setup.exe` 2.65 -> 6.3 MB.** That is
     the AV1 encoder and it is irreducible.
     Three traps, one per failed run:
     (a) **Do not pass `-DENABLE_NASM=ON` to aom.** It routes the build through `test_nasm()`,
         which greps `nasm -hf` for the string `-Ox` and rejects the nasm in `fedora:latest`
         ("multipass optimization not supported"). aom looks for **yasm** first and only runs that
         test when the assembler is nasm, so installing yasm and passing no flag skips the whole
         question. (The nasm here, 2.16.03, does print `-Ox` -- the container's is something else.)
     (b) In `win/deps.sh`, only `build()` copied the staging tree into the sysroot, and it runs
         before `license()`. Every library but the last was carried over by the next one's build;
         libavif's licence never arrived and the MSI failed on the missing file. `license()` syncs
         too now.
     **Phase 3 (writing .heic) builds green in CI, first try, not yet tried on Windows** (runs
     `35773656438`, `35774134563`): kvazaar 2.3.2 as a DLL, libheif's summary shows "Kvazaar HEVC
     encoder: + built-in", zip 8.0 -> 8.46 MB. **Correction: kvazaar is BSD-3 since 2.0, not LGPL**
     as this file used to say -- still the reason to prefer it over x265 (GPL). Trap found before it
     bit: the per-library cache markers carry the version only, so turning `WITH_KVAZAAR` on would
     have been ignored by a libheif restored from the phase-2 cache; its marker is now
     `heif-<ver>+kvazaar`, and `win/deps.sh`'s header says a flag change needs a new marker name.
     Also fixed in the same round (user report): Settings > Apps showed "2.0" for the NSIS install
     and "2.0.0" for the MSI, each hard-coded separately; `win/dist.sh` now reads `nova.li` and
     passes it (`makensis -DVERSION`, `wixl -D Version`). The MSI can only hold the numeric part
     (ProductVersion is numbers only), so it shows 2.0.0 where NSIS shows 2.0.0-beta.2.
     Also (user report): NSIS installed per machine into `Program Files (x86)` -- the installer is
     32-bit, so `MultiUser.nsh` defaulted to `$PROGRAMFILES` for a 64-bit `nova.exe`. Fixed with
     `MULTIUSER_USE_PROGRAMFILES64` (the MSI already used `ProgramFiles64Folder`); an older
     `(x86)` install is not moved, uninstall it first.
     **Release assets, decided with the user and built (run `35778801993`, all green):**
     `nova-<version>-<os>-<arch>` everywhere -- the shape `release/pack.sh` already gave Linux and
     macOS, so `install.sh` did not change. The user wanted the version in the name (so no
     permanent `latest/download/` links; the README points at the releases page). Windows now
     ships `nova-<v>-windows-x86_64-setup.exe`, `.msi` and `.zip`, each with a `.sha256` (it had
     none). Rejected: `.dmg` (for `.app` bundles, and Gatekeeper blocks one that is not
     notarized), `7z` (Windows opens zip natively), a hand-made source tarball (GitHub attaches
     one to every release). **Linux arm64 is new** (`ubuntu-24.04-arm`, free for public repos;
     `install.sh` already mapped aarch64 to arm64 and asked for that archive, which never
     existed). Its binary really ran there (`nova --version`). **CI builds only the Lisaac compiler now
     (user's idea, run `35780354280`, green first try on all four builds):** Lisaac Omega's own
     `install.sh` also builds `elit`, its editor (GL, GLFW, an x86_64-only `libglfw3.a` that fails
     to link on arm64), and edits `~/.bashrc`. Compiling nova needs `bin/lisaac` (one `gcc -O2` of
     `bin/lisaac.c`, the installer's own command), `lib/` and `make.lip` -- ~15 MB of the 61 MB
     zip -- plus, on macOS, the `target := "apple"` the installer writes into `make.lip` (it
     swaps `-flarge-source-files`, which Apple's clang rejects, for `-w`). Verified locally first:
     nova built against that trimmed tree is the same 307144 bytes and round-trips an image. The
     apt/brew dependency steps, the elit-failure workaround and the find-based PATH guess are gone;
     cache key is `lisaac-compiler-<os>-<arch>-<version>-<etag>` (`3416f88`): lisaac.org
     **republishes under the same version number** -- 0.6 was replaced in place on 2026-09-22
     17:02 UTC -- so the version alone would keep a stale compiler silently; the zip's ETag is read
     with `curl -I` in the version step. The caches then in use dated from 20:27 UTC that day, so
     beta.3 was already built with the new 0.6; locally too (same sha256 `f76aa4b2...`). `c-source` is uploaded by the x86_64 Linux
     job only (two jobs uploading one name would fail).
     (c) **`win/dist.sh` now fails the build when a DLL it packages is absent from `win/nova.wxs`**
         -- the trap that shipped an MSI without libheif, since `wixl` says nothing about a file
         missing from its explicit list. Predicting `libaom.dll`/`libavif.dll` correctly was luck;
         the check is what makes it not matter next time.
  3. `install.bat` did not self-elevate, so a double-click failed with `0x80040201`
     (`SELFREG_E_CLASS`) -- `DllRegisterServer` writes to `HKEY_CLASSES_ROOT` and `HKLM`
     (`plugins/wic/nova_wic.cpp:294`, `:334`) and returns that for any failed write. A `regsvr32`
     from an elevated shell registers fine (confirmed: `HKCR\.nova` present with `NOVA.Image`,
     `image/x-nova`, `PerceivedType: image`). **Fixed**: both `.bat` files test `net session` and
     relaunch themselves through `Start-Process -Verb RunAs`.
  4. Mark-of-the-Web: everything extracted from a downloaded zip is marked, so PowerShell refuses
     to run `nova.ps1` with a prompt that never names the cause. The zip's README.txt now opens
     with `Get-ChildItem -Recurse | Unblock-File`.
- **PowerShell completion: both installers now set it up themselves, no opt-in, no user step**
  (`6da516a`, `7e18edb`, and the both-hosts commit). PowerShell has no auto-load directory for
  argument completers, so a `$PROFILE` line is the only mechanism. `nova-profile.ps1` (generated by
  `win/dist.sh`, so the zip has it too) adds or `-Remove`s that line, and **PowerShell edits its own
  profile** rather than NSIS or MSI doing it. The earlier shape -- an off-by-default NSIS component,
  and the MSI shipping the script for the user to run -- was the user's call to drop ("c'est une
  idée de merde"): shipping a script and saying "run it yourself" is a limit presented as a design.
  Four things that took a try each, worth not rediscovering:
  1. Active Setup alone is not enough: it only fires at the *next logon*. Both installers now run
     the script immediately as well (UAC elevates the same account on a personal machine, so the
     profile written is the right one) and keep Active Setup for the case that breaks -- other
     credentials at the UAC prompt -- and for the other users of a per-machine install. The script
     is idempotent, so both paths running cannot double the line.
  2. **The MSI custom action must be `immediate` and sequenced after `InstallFinalize`.** A
     `deferred` action resolves no property, so `[INSTALLDIR]` would stay literal; anything
     sequenced earlier runs before the files are on disk.
  3. **Never `Set-Content` a file the user owns.** It rewrites the whole thing, and Windows
     PowerShell 5.1 -- the host both installers call -- writes ANSI by default, so a UTF-8
     `$PROFILE` with accents came back mangled. It appends with `Add-Content` now; only a removal,
     or replacing a line left by an install in another directory, still rewrites. Sub-trap the test
     caught: appending to a profile whose last line has no trailing newline glues the line onto it,
     and the next run then sees that as stale and rewrites anyway -- add the newline first.
  4. **`$PROFILE` is per host**: 5.1 and PowerShell 7 read different files, and the installers only
     ever call 5.1, so a PowerShell 7 user got nothing. The script hands itself to the other host
     when that one is installed (`-ThisHostOnly` stops the bounce-back) -- one place instead of the
     four call sites (zip, NSIS, MSI, Active Setup).
  All of it verified under pwsh 7.6.6 against a fake profile (byte-for-byte check that the user's
  existing content is untouched, idempotence, `-Remove`, the relaunch's arguments through a shim),
  plus `makensis -V3` and `wixl` -- both installers build locally here, no CI round-trip for a
  syntax check.
- **MSI error 2762 on uninstall: found and fixed.** Reported first as "code 126 or 127"; the
  screenshot said 2762, which is exact -- "cannot write script record, transaction not started",
  i.e. a *deferred* custom action sequenced outside the install transaction. **`wixl` ignores a
  `<Custom>`'s `After=` and numbers the actions in document order**, so `RefreshRemove` sat at
  6603, past `InstallFinalize` (6600), whatever it claimed to follow -- `RemoveRegistryValues` is
  not even in the emitted table. Made immediate (type 1089 -> 65), which is right there anyway: the
  keys are gone by then and the action only tells the shell so. Pre-existing, unrelated to the
  completion work, and only ever visible on an MSI uninstall. Lesson for any future `.wxs` change:
  **read the sequence table back** (`msiinfo export nova-setup.msi InstallExecuteSequence`) instead
  of trusting `After=`, the same way the MSI's missing DLLs were only caught by comparing sizes.
  Worth remembering about the report itself: a remembered error code sent the diagnosis toward two
  dead ends (a missing DLL dependency, a missing export -- both disproved with `objdump -p`); the
  screenshot settled it in one step. Ask for the exact text first.
- **Trap found the hard way: never ship a `.ps1` named after the command into a PATH directory
  (47c4666).** On the user's machine every `nova` command printed nothing, wrote nothing and set no
  exit code -- `(Get-Command nova).Source` was `C:\Program Files (x86)\NOVA\nova.ps1`, the completion
  script, which only registers an argument completer. PowerShell had picked the script over
  `nova.exe` in the same directory. Shipped as `nova-completion.ps1` now (zip, NSIS and MSI);
  `completions/nova.ps1` keeps its name in the repo, where it is never on a PATH. Unexplained: the
  identical layout ran `nova.exe` correctly on the previous install, so something machine-side
  (`PATHEXT`, or PATH order) decides it -- the rename removes the ambiguity either way.
- **`libwinpthread-1.dll` was missing, which is why RAW still failed after LibRaw shipped.** After
  the rename `nova.exe` ran but still said "libraw not found". Loading each DLL by hand on the real
  machine (`LoadLibraryEx` with `LOAD_WITH_ALTERED_SEARCH_PATH`, 8, so dependencies resolve next to
  the DLL) named the culprit: `libgcc_s_seh-1.dll` failed with 126 (`ERROR_MOD_NOT_FOUND`), and
  `libstdc++-6.dll` and `libraw_r-25.dll` failed through it. Both import `libwinpthread-1.dll`,
  which the earlier `objdump` closure walk had missed and nothing checked. **`win/dist.sh` now asks
  every staged DLL what it imports and fails the build when an import that exists in the MinGW
  sysroot is not in the package** -- the check that would have caught this before it reached a real
  machine; the closure is verified complete on the current build. **Confirmed working on the user's
  real Windows machine on 2026-09-21**: `nova encode IMG_2557.CR3 test.nova` writes the file.
  Two diagnostic traps worth keeping: `LoadLibrary` with a *full path* resolves the DLL's own
  dependencies against the **calling process's** directory (so a probe from `powershell.exe` looks
  in System32 and fails for reasons that say nothing about nova) -- pass flag 8 instead. And a
  PowerShell session that successfully loaded one of these DLLs keeps it locked, so the next
  install fails with "Error opening file for writing": close that window first.
- **macOS: tested for real (user's MacBook Air M4, ARM64).** `./build.sh` compiles and installs the
  core `nova` CLI cleanly -- confirmed working (`nova encode`/`decode` round-trip). Found and fixed
  a real cross-platform bug (`072f6f7`): `libnova/novadec.c` unconditionally defined
  `_POSIX_C_SOURCE 200809L`, which on Darwin (unlike glibc, where it's purely additive) hides Apple's
  own extensions instead of just adding POSIX ones -- broke `sysconf(_SC_NPROCESSORS_ONLN)`, used to
  size the decoder's thread pool. Fixed by not defining it under `__APPLE__` (macOS's default
  feature-test macros already expose what's needed). After the fix, `plugins/qt` also builds and
  installs cleanly on macOS via `./build.sh` -- untested in an actual Qt app (user has none on this
  Mac to try it with). KDE/GNOME plugins correctly skipped (not applicable on macOS).
  `update-mime-database not found` is expected, not a bug -- macOS has no shared-mime-info framework.
  **No native Finder/Quick Look/Preview support yet** (would need a new ImageIO plugin, comparable in
  scope to `plugins/wic` on Windows -- code signing, notarization and app-extension sandboxing all
  have their own untested pitfalls). Decision: deliberately deferred past the v2 release rather than
  rushed in -- ship v2 with a working CLI on macOS and the native plugins nova already has elsewhere
  (Windows WIC, Linux Qt/KDE/GNOME/GTK), build and test the ImageIO plugin properly afterward.
- **GNOME testing (real VM, Fedora 44 + GNOME Shell 50, glycin 2.1.5): in progress.** `plugins/qt`
  and `plugins/gdk-pixbuf` installed and built cleanly via `./build.sh` there (Qt plugin works even
  outside KDE). `plugins/kde` correctly skipped (no KF6KIO on a GNOME box, expected).
  **`plugins/glycin` install was broken, fixed (`c8c4bb8`), not yet re-verified:** `install.sh`
  assumed `glycin-2.pc` exposes a `loaderdir` pkg-config variable -- it doesn't on glycin 2.1.x, so
  the build was always skipped. Root-caused by dumping the real `.pc` file and `rpm -ql
  glycin-loaders` on the test VM: loaders live under a versioned, convention-based directory
  (`/usr/libexec/glycin-loaders/2+/`, `/usr/share/glycin-loaders/2+/conf.d/`), derived from the
  `.pc`'s own `prefix` variable instead. Also found nova's glycin loader never shipped a `.conf` file
  registering it for `image/x-nova` (checked `glycin-svg.conf`'s format on the same machine to get
  it right) -- even a correctly-placed binary was invisible to glycin without one; `install.sh` now
  generates and installs it (`ec10155`). Also fixed: double-click on a `.nova` said "no application
  installed" even with a working loader, because GNOME resolves the default app for a MIME type from
  `mimeapps.list`, not from which loader can technically decode it -- `install.sh` now runs
  `xdg-mime default org.gnome.Loupe.desktop image/x-nova` when Loupe is present (`ec10155`).
  **Open, not chased further: Nautilus itself won't generate a `.nova` thumbnail** (generic icon
  shown, a `~/.cache/thumbnails/fail/gnome-thumbnail-factory/` entry appears every time) even though
  `glycin-thumbnailer` invoked by hand on the exact same file, at every XDG thumbnail size
  (128/256/512/1024), succeeds and produces a real PNG. Ruled out on the real VM: bwrap sandboxing
  works generically, SELinux isn't denying anything (`ausearch -m avc` clean, binary correctly
  labelled `bin_t`), no seccomp kill (`ausearch -m SECCOMP`/`ANOM_ABEND` empty -- the process likely
  never spawns at all, rather than being killed), not a `--size`-dependent decoder bug, and not a
  general glycin/VM problem (an SVG in the same folder thumbnails fine). Two more targeted fixes
  tried together and still no thumbnail: using `glycin-thumbnailer`'s absolute path in the
  `.thumbnailer` file (now done anyway in `install.sh`, matches the convention every other
  glycin-shipped `.thumbnailer` uses) and removing the competing `gdk-pixbuf`-based `nova.thumbnailer`
  in case its `TryExec` fallback wasn't working as assumed. Stopping here: Loupe opens `.nova` fine
  through the same glycin loader (both the format and the loader are proven correct), double-click
  works via the `xdg-mime default` fix above -- thumbnails are a nice-to-have, not a blocker, and
  further debugging would mean instrumenting glycin's own sandboxed spawn path, out of scope for now.
- The update check's Windows/WebAssembly branches are untested for lack of a runtime here to execute
  them (only to compile).
- Plugin test status (real machines): `plugins/qt` and `plugins/kde` built and installed cleanly on
  Fedora KDE (`cmake -S plugins/{qt,kde} -B build-... && cmake --build ... && sudo cmake --install
  ...`), `.nova` thumbnails confirmed showing in Dolphin (noticeably slower than a JPEG thumbnail --
  a real `nova` decode per thumbnail, not investigated further, likely expected). `plugins/wic`
  (Windows Explorer) confirmed working too: `win/build.sh` and `plugins/wic/build.sh` cross-compile
  fine on Fedora (MinGW-w64, already installed) -- only `nova.exe` and `nova_wic.dll` need to reach
  the Windows machine, no MinGW/MSYS2 needed there, just `regsvr32 nova_wic.dll` as admin. Confirmed
  the modern Windows Photos app cannot use third-party WIC codecs regardless of format (sandboxed) --
  `.nova` opens in the legacy Windows Photo Viewer instead, as README.md already documented;
  `win/dist.sh`'s own bundled README.txt wrongly said "Photos" -- fixed to name Photo Viewer and
  say Photos won't open it. `plugins/gdk-pixbuf` and `plugins/glycin` (GNOME) have no test
  environment available (user's other machine is Windows, not GNOME) -- untested, no plan yet.
- **Code signing on Windows: open, worth doing eventually.** `nova-setup.exe` is unsigned, so
  SmartScreen shows "Windows a protégé votre ordinateur / Éditeur inconnu" and needs
  "Informations complémentaires" -> "Exécuter quand même". Removing that needs an Authenticode
  signature, which is a paid certificate in the general case: since June 2023 every code-signing
  certificate requires the private key on a hardware token or a cloud HSM, which killed the cheap
  file-based certificates. Options, best fit first:
  **SignPath Foundation** -- free signing for open-source projects, certificate plus a signing
  service that plugs into CI. The right fit here (nova is MIT and already built by GitHub Actions);
  costs an application and meeting their eligibility rules.
  **Azure Trusted Signing** -- Microsoft's own, about $10/month, but wants a verifiable legal
  identity and the bar is higher for an individual than for a company.
  **A plain OV certificate** (~200-400 EUR/year) does *not* clear the warning on its own:
  SmartScreen still wants reputation built up over weeks. Only an **EV certificate**
  (~300-600 EUR/year, hardware token) gets reputation from the first download.
  Two things that decide the shape of this: a self-signed certificate is useless (the user would
  have to install the root by hand, worse than the warning), and for an unsigned binary SmartScreen
  reputation is tied to the file hash, so every new build starts from zero -- signing is the only
  way reputation carries from one release to the next. Prices and eligibility move; check the sites
  before committing (figures here date from 2026-09-20).

### Traps
- This sandbox's `test/all.sh` will show FAIL on `tiff`/`jpeg`/`webp`/`heif` (missing
  `test/photos/screenshot.png` -- gitignored, user's own photos, not present here). Environment gap,
  not a regression -- verify against a specific code change before assuming a real bug.
- `test/update.sh` (needs `script(1)` for a fake pty) flakes when launched as a background task with
  no real tty attached (fails after 2 checks, ~1s) but passes "ALL OK" run directly in a terminal.
  `script` itself is installed here -- re-run in foreground before trusting a background FAIL on it.
- Any test step that shells out to `uv`/python (`test/meta.sh`, `test/unit.sh`'s corrupt-file fuzz)
  fails under the bash sandbox with `~/.cache/uv` read-only -- not a real bug, just re-run that one
  command with the sandbox disabled.
- A Lisaac library class used as a bare expression (e.g. `Img_jpg`, `Img_png` in
  `lib/draw/img/image.li`'s `coder := Img_jpg`) is a **shared singleton instance**, not a fresh
  object -- its internal buffers persist and get reused across calls. Caused the JPEG-animation
  frame-aliasing bug above; any code storing what such a class's method returns must copy it
  immediately, never keep the reference.
- Lisaac drops a `(c != NULL)` test on a `C_array` that came from a backtick C expression (assumes
  non-NULL) -- the call then crashes on NULL. Test for NULL inside the C expression instead:
  `` (`f() != 0`:Int = 1).if {...} `` (see `nova_update.li`).
- A background child started just before nova exits in a pty dies of SIGHUP when the terminal
  closes; nova ignores SIGHUP itself right before spawning (inherited through fork/exec).
- `Nova_par` reaps any child (`waitpid(-1, ...)`), so never start a background process before its
  jobs are done.
- The prior session's home-wiping incident: an ad hoc test command set `S=...` in the outer shell
  and ran a separate `t.sh` in a fresh `bash` -- `$S` was never exported, so `rm -rf $S/home` became
  `rm -rf /home`. Fix: `test/install.sh` is one file, no cross-script variable handoff, `set -eu`,
  and a path-prefix check before its one `rm -rf`.
- **`lisaac -split` (parallel C compile, per the user's teacher) does not build nova** (checked
  2026-09-24): it splits the C into ~20 files, but the C that nova's modules embed (`np_*`, `nh_*`,
  `nw_*`, `nr_*`... statics and globals) stays in one of them, so the others fail on implicit
  declarations and the link fails. Making it work = moving that C into a real `.c` + header (static
  state must stay single). Gain too small for now: a full `-boost` build is 8.5 s on 4 cores here.
- bash `local x` **without** an assignment is genuinely *unbound* under `set -u`.
- `set -e` only aborts on the *last* command in a `&&`/`||` chain failing, and only propagates that
  exemption into a called function when the function itself is invoked as that guarded chain.
  Several `install.sh` plugin call sites use `if ...; then ... || true; fi` because of this -- and
  `run()`'s own body must use `if "$@"; then status=0; else status=$?; fi`, not a bare `"$@"`, or
  set -e exits before the failure-diagnostic line ever prints.
- `grep -c PATTERN file` prints `0` but **exits 1** when there are zero matches.
- Deleting/rebuilding `./nova` while a background test run (`test/all.sh` et al.) is still using it
  produces confusing, non-reproducible FAILs -- always let a background test finish (or run in an
  isolated copy) before touching the binary it's testing.
