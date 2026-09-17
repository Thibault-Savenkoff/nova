## Current state

_Updated 2026-09-17._

### Decisions
- Distribution plan for v2 (6 steps), **all done**: 1. `nova --version` (`26cd6b9`) 2. `install.sh` +
  `release/pack.sh` (`a932e96`) 3. `build.sh` (`111e811`) 4. GitHub Actions release job (`183d32e`,
  verified green) 5. daily, quiet update check (`c424a79`) 6. README (`c32f58d`). Still open: a
  public `v2.0.0-beta` pre-release goes out only after the user reviews the exact GitHub page/command
  (no `v2.*` tag pushed yet -- `install.sh`'s download path is untested against a real release).
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
- Next: publish the `v2.0.0-beta` pre-release (user reviews first), then a real Linux desktop run of
  `install.sh`'s plugin step, and someone actually running the CI's macOS binary once.

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
