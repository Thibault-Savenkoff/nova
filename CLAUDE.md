## Current state

_Updated 2026-09-17._

### Decisions
- Distribution plan for v2 (6 steps), **all done**: 1. `nova --version` (`26cd6b9`) 2. `install.sh` +
  `release/pack.sh` (`a932e96`) 3. `build.sh` (`111e811`) 4. GitHub Actions release job (`183d32e`,
  verified green) 5. daily, quiet update check (`c424a79`) 6. README (`c32f58d`). Still open: a
  public `v2.0.0-beta` pre-release goes out only after the user reviews the exact GitHub page/command
  (no `v2.*` tag pushed yet -- `install.sh`'s download path is untested against a real release).
- `win/nova.nsi` rewritten around NSIS's `MultiUser.nsh` + `MUI2.nsh`: a wizard page now lets the user
  pick a per-machine (HKLM, needs elevation) or per-user (HKCU) install, license page added, and
  `ManifestDPIAware true` fixes the installer being blurry at non-100% Windows scaling. Also fixes the
  publisher name casing (was "Thibault Savenkoff", should be "Thibault SAVENKOFF" -- same fix applied
  to root `LICENSE` and `win/nova.wxs`). Build-tested here with `makensis` (fake `dist/nova-windows/`
  files) -- not yet tested by actually running the installer on Windows. `win/nova.wxs` (the MSI) is
  still per-machine only; user didn't ask for per-user there yet.
- Icon quality (user-reported, real Windows test) is not fixable from here: needs a new multi-resolution
  `win/nova.ico` asset, which nobody has supplied.
- Missing system deps (cmake, Qt-devel, libheif...) are never auto-installed
  by install.sh/build.sh -- detected and skipped with a printed command to
  copy-paste instead. User's explicit call: auto-installing packages across
  distros needs sudo and can break a system, too risky for what this is.
- `install.sh --uninstall` is manifest-only: every file and rc-file line it
  writes is recorded in `$prefix/share/nova/installed.txt`, and uninstall only
  ever `rm -f`s a single path read back from that file -- never a directory,
  never a computed/guessed path. This is deliberate, not incidental (see Traps).
- `NOVA_TEST_ROOT` env var redirects root-owned plugin installs (Qt/KDE system
  dirs, gdk-pixbuf loader dir, `/usr/share/thumbnailers`) into a fake root via
  `DESTDIR`/path-prefixing, so `test/install.sh` never needs real sudo.
- glycin loader install path is found via `pkg-config --variable=loaderdir
  glycin-2` rather than a hardcoded guess -- unverified on a real GNOME
  machine (none available here); skips cleanly with a warning if absent.
- Model: user is on Claude Pro. Tell them which /model and /effort to set before each significant
  task. Opus 5 `high` is on trial for the Lisaac work; if it eats the quota, Sonnet 5 (any effort)
  and Opus only at `low`.
- Update check: terminal only (isatty(2)), at the very end of `main`, reads a cached GitHub
  release list and refreshes it in the background with curl at most once a day (cache mtime is
  touched before spawning, so a loop over files spawns one curl). Cache:
  `$XDG_CACHE_HOME/nova/releases.json` or `~/.cache/nova/`, `%LOCALAPPDATA%\nova\` on Windows.
  Only tags of nova's own major version count (v1 releases exist on the same repo).
- Lisaac Ω 0.6 is installed in the sandbox at `/home/agent/tools/lisaac/bin/lisaac` (on PATH via
  `/etc/sandbox-persistent.sh`); only `bin/lisaac.c` was compiled, not elit (needs OpenGL).

### In flight
- The update check's Windows branch (`_mkdir`, `move /y`, `_spawnl` via `Environment.run`) and the
  WebAssembly build (`#ifdef __EMSCRIPTEN__` returns early) compile untested: no MinGW / emcc here.
- Not yet tested end-to-end: install.sh's plugin builds (cmake/pkg-config/cargo
  aren't installed in this sandbox), and the whole thing on macOS. Reviewed by
  reasoning + shellcheck instead; treat a first real Linux desktop run (Qt/KDE
  present) as the next real test before trusting the plugin-install paths.
- Gating the `v2.0.0-beta` pre-release: a 5-part manual test list from the user (their machines, not
  this sandbox -- Windows install/uninstall first since it conditions the installer's quality; then
  the web page on iPhone+PC, real photos round-trip, IrfanView, GIMP; GNOME and macOS untestable by
  either of us right now). User reports each result here as they run it; fix what breaks.
- Test 1 (Windows install/uninstall) results, from a real run: 1.2/1.3/1.4 all pass. Bugs found and
  fixed above (name casing, NSIS user/system + DPI + license). Icon quality flagged, not fixed (needs
  a new asset). Not yet re-tested on real Windows after this round of fixes.
- Real bug found and fixed: decoding a `.nova` to an unrecognized extension (e.g. `nova decode x.nova
  x.cr3`, since CR3 was never a supported decode target) silently wrote a PNG's bytes under that name
  instead of failing -- `write_image`'s extension dispatch (nova.li) had no `else { fail }`, just a
  bare "anything else is PNG" fallback. Fixed and round-trip verified (`.png` still works, `.cr3` now
  fails with a clear message) with the sandbox's local `lisaac` compiler.
- `test/unit.sh` re-run after the `write_image` fix: all OK, 2768 tests / 0 failed, 720 corrupt files
  decoded without a crash -- no regression.

### Traps
- Lisaac drops a `(c != NULL)` test on a `C_array` that came from a backtick C expression (assumes
  non-NULL) -- the call then crashes on NULL. Test for NULL inside the C expression instead:
  `` (`f() != 0`:Int = 1).if {...} `` (see `nova_update.li`).
- A background child started just before nova exits in a pty dies of SIGHUP when the terminal
  closes; a `trap '' HUP` in the spawned `sh -c` loses the race. nova ignores SIGHUP itself right
  before spawning (inherited through fork/exec).
- `Nova_par` reaps any child (`waitpid(-1, ...)`), so never start a background process before its
  jobs are done.
- The prior session's home-wiping incident (before this sandbox existed): its
  ad hoc test command set `S=...` in the outer (zsh) shell and then ran a
  separate `t.sh` in a fresh `bash` process -- `$S` was never exported, so
  inside `t.sh` it was empty, and a `rm -rf $S/home`-shaped cleanup became
  `rm -rf /home`. Root cause is inferred, not proven (`t.sh` no longer exists).
  Fix applied here: `test/install.sh` is one file, no cross-script variable
  handoff, `set -eu`, and a path-prefix check (`case $T in "${TMPDIR:-/tmp}"/*)
  ...`) before the one cleanup `rm -rf`.
- bash `local x` **without** an assignment is genuinely *unbound* under
  `set -u` (not empty-but-set) -- verified empirically. Every `local` in
  `install.sh` was audited to assign-before-read.
- `set -e` only aborts on the *last* command in a `&&`/`||` chain failing, and
  only propagates that exemption into a called function when the function
  itself is invoked as that guarded chain -- also verified empirically. Several
  plugin call sites in `install.sh` were rewritten from `cmd && cmd` to
  explicit `if ...; then ... || true; fi` because of this.
- `grep -c PATTERN file` prints `0` but **exits 1** when there are zero
  matches -- bit `test/install.sh`'s own line-counting helper (fixed).
