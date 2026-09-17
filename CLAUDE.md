## Current state

_Updated 2026-09-17._

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

### Decisions
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
  again; Sonnet 5 (any effort) otherwise.

### In flight
- Real bug found (real Windows test) and fixed: decoding to an unrecognized extension (e.g.
  `nova decode x.nova x.cr3`) silently wrote a PNG under that name instead of failing --
  `write_image` (nova.li) had no `else { fail }`. Fixed, verified (round-trip + `test/unit.sh`:
  2768 tests / 0 failed).
- Test 1 (Windows install/uninstall) done once for real: binary/completion/mime/uninstall all pass;
  found and fixed the CR3 bug, name casing, and the NSIS issues above. Not yet re-tested on real
  Windows since. Tests 2-5 (web page, real photos, IrfanView, GIMP) still pending from the user.
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
