## Current state

_Updated 2026-09-18._

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
  verified green), daily quiet update check (`c424a79`), README (`c32f58d`). Still open: a public
  `v2.0.0-beta` pre-release goes out only after the user reviews the exact GitHub page/command (no
  `v2.*` tag pushed yet).
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
  `.wxs`), since `install.sh` never runs on Windows; not auto-wired into `$PROFILE`. cmd.exe has no
  hook for a third-party program's argument completion -- nothing shipped for it.
- Icon quality: stale note, checked and closed. `win/nova.ico` (`0d9eef0`) is already multi-resolution
  (256/64/48/32/24/16 px) and legible down to 16 px -- no further work needed.
- Missing system deps (cmake, Qt-devel, libheif...) are never auto-installed by install.sh/build.sh
  -- detected and skipped with a printed command to copy-paste. Deliberate: auto-installing across
  distros needs sudo and can break a system.
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
- PowerShell completion (`completions/nova.ps1`): not yet tested -- no `pwsh` here (not in Fedora's
  default repos) and it's Windows-only anyway; next step is testing it directly on the user's
  Windows machine (already used for the `wic` plugin test).
- macOS: no test environment available, no plan yet.
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
