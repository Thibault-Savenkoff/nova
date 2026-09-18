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
- Icon quality (real Windows test) needs a new multi-resolution `win/nova.ico`; nobody has supplied
  one yet.
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
  3. **DNG output had no embedded thumbnail** -- still being worked on, kept OUT of the commit
     above, working tree only. See its own entry below; two attempts so far have not produced a
     visible thumbnail on the user's machine.
- **DNG thumbnail attempt log (not committed, not working yet):**
  - Attempt 1: `Nova_tiff.write_dng` now optionally appends a second, Exif-thumbnail-style IFD1
    (`NewSubfileType 1, Compression 6, JPEGInterchangeFormat/Length`) after the main pixel data,
    sourced from the RAW's own PREV chunk (LibRaw half-size preview, already in every RAW `.nova`).
    Result: no thumbnail. Root cause found: `write_dng` calls `start` as its first statement, and
    `start` resets `thumb_n := 0` -- but the call site set the thumbnail via `Nova_tiff.set_thumb`
    *before* calling `write_dng`, so `start` wiped it before `finish` ever saw it.
  - Attempt 2: fixed the ordering (`write_dng` now takes `thumb (t, tn, tw, th)` as parameters and
    calls `set_thumb` itself, right after `start`). Also speculatively added a `BitsPerSample`
    (258) entry, reasoning some TIFF readers require it. Result on the user's machine: still no
    thumbnail.
  - **Do not add a third speculative tag.** Per outside review: BitsPerSample was very unlikely to
    be the real blocker (extractors that read tags 513/514 just grab the JPEG byte range) and was
    added without any local verification -- net risk, not progress. The actual next step is a
    Python script the user can run on their *existing* `out.dng` (no rebuild needed) that parses
    IFD0's next-IFD-offset and, if non-zero, IFD1's tags and the JPEG SOI/EOI bytes at the claimed
    offset. That number tells us which of two completely different bugs this is: (a) next-IFD-offset
    is still 0 -> nothing was ever written, most likely because the user tested against a stale
    binary (they install to `~/.local/bin`, separate from the repo's `./nova`) rather than a real
    IFD1 bug -- ask them to test with `./nova` directly from the repo to rule this out; or (b) a
    valid IFD1 with a real JPEG inside it exists but no viewer shows it -- meaning the bytes are
    fine and the real problem is that DNG readers (Gwenview via LibRaw/KImageFormats) look for
    previews via SubIFDs (tag 330) rather than the classic Exif IFD1 next-pointer chain, which is a
    different, bigger fix. Do not touch `nova_tiff.li` again until this comes back.
  - Also useful: `finish`'s IFD1 code path is shared by `write_image`'s TIFF output (mode 1), so it
    can be exercised and checked byte-for-byte with `test/corpus/*.png` alone -- no CR3, no LibRaw
    needed -- via a test-only env-var hook (mirroring the existing `NOVA_RECON`/`NOVA_GAINMAP`
    pattern) that isn't built yet. Would turn this into a one-second local loop instead of a
    one-message-per-attempt loop with the user. Worth building before attempt 3.
- `nova decode raw.nova out.pgm` "looks black" -- confirmed non-bug. User checked pixel extrema
  (`1943, 16383`): real sensor data, not black; just a naive linear view of unprocessed raw values
  (expected, per MANUAL.md -- the bare sensor frame has no demosaic/white-balance/gamma). Closed.
- HDR gain map (#18): user tested a real iPhone HEIC with a GMAP chunk -> Ultra HDR JPEG. Gwenview
  "pas terrible", darktable shows the same image as the source HEIC either way. Likely not a nova
  bug: `write_ultrahdr`'s own comment says "SDR viewers show the SDR image", and neither Gwenview
  nor darktable are known to support Ultra HDR gain maps (a 2023 format, mainly Android/Chrome
  support so far) -- darktable showing the unmodified SDR base image is probably the *correct*
  fallback, not evidence the gain map is broken. Offered to write a segment-dump script to check
  the MPF/XMP gain map structurally if the user wants; not done yet, no response.
- HDR `-hdr` rendering differences (#17): user says results differ "visuellement" between decoded
  formats/options but hasn't said which pair -- MANUAL.md documents that `-hdr` legitimately looks
  different per viewer (raw PQ, "burnt, cyan skies" without tone-mapping) so this may also be
  expected. Still open, waiting on the user for which exact files/options they compared.
- Real bug found earlier (real Windows test) and fixed: decoding to an unrecognized extension (e.g.
  `nova decode x.nova x.cr3`) silently wrote a PNG under that name instead of failing --
  `write_image` (nova.li) had no `else { fail }`. Fixed, verified (round-trip + `test/unit.sh`:
  2768 tests / 0 failed).
- Test 1 (Windows install/uninstall) done once for real: binary/completion/mime/uninstall all pass;
  found and fixed the CR3 bug, name casing, and the NSIS issues above. Not yet re-tested on real
  Windows since. The user's `~/test_nova/Tests.md` pass above covers most of tests 2-5's ground
  (encode/decode/metadata/bench/RAW on real files) though not run through IrfanView/GIMP specifically.
- Not yet tested end-to-end: install.sh's plugin builds (cmake/pkg-config/cargo aren't installed in
  this sandbox), the whole thing on macOS, fish and PowerShell completion behavior (no fish/pwsh
  here -- only syntax-checked), and the update check's Windows/WebAssembly branches (no MinGW/emcc
  runtime here to execute them, only to compile).

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
