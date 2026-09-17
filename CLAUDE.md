## Current state

_Updated 2026-09-17._

### Decisions
- Distribution plan for v2 (6 steps): 1. `nova --version` (done, `26cd6b9`) 2.
  `install.sh` + `release/pack.sh` (done, `a932e96`) 3. `build.sh` 4. GitHub
  Actions release job (Linux + macOS binaries) 5. daily, quiet update check in
  `nova.li` 6. README. A public `v2.0.0-beta` pre-release only goes out after
  the user reviews the exact GitHub page/command.
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
- Model: session runs Sonnet 5 at effort `high`, not Opus -- user is on a
  Claude Pro plan, and effort matters more than model choice for this kind of
  careful-shell-scripting correctness work.

### In flight
- `install.sh`, `release/pack.sh`, `test/install.sh` are committed on `v2`
  (`a932e96`) and pass `test/install.sh` locally (install/re-run/uninstall/
  corrupt-archive/--from/unknown-version/--help, 17 checks). **Not yet pushed**:
  `git push origin v2` failed with no GitHub credentials in this sandbox: user
  needs to run `sbx secret set github --sandbox claude-nova -t "$(gh auth
  token)"` on their host, then the push can be retried.
- Not yet tested end-to-end: the actual plugin builds (cmake/pkg-config/cargo
  aren't installed in this sandbox), and the whole thing on macOS. Reviewed by
  reasoning + shellcheck instead; treat a first real Linux desktop run (Qt/KDE
  present) as the next real test before trusting the plugin-install paths.
- Next: `build.sh` (build-from-source path, for people who have Lisaac), then
  the GitHub Actions release workflow.

### Traps
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
