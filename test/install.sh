#!/bin/bash
# Installs and uninstalls YAIF via install.sh, end to end, against a fake local
# release server. Never touches the real $HOME: every install.sh run below gets
# its own throwaway HOME under a fresh mktemp dir, passed explicitly through
# env -i so nothing relies on a variable happening to still be exported.
# Run from the repository: test/install.sh
set -eu
cd "$(dirname "$0")/.."

T=$(mktemp -d)
# The lesson this script exists for: a previous install.sh test wiped a real
# $HOME because a variable it relied on wasn't actually set where it was used.
# So: verify $T is really a fresh directory under the system temp dir before
# anything is ever allowed to rm -rf it.
case $T in "${TMPDIR:-/tmp}"/*) ;; *) echo "test/install.sh: unsafe mktemp path: $T" >&2; exit 1 ;; esac

srv_pid=
fail=0
cleanup() {
  [ -n "$srv_pid" ] && kill "$srv_pid" >/dev/null 2>&1 || true
  if [ "$fail" = 0 ]; then
    case $T in "${TMPDIR:-/tmp}"/*) rm -rf -- "$T" ;; esac
  else
    echo "logs and homes kept: $T"
  fi
}
trap cleanup EXIT

check() {  # check <name> <condition...>
  local name=$1; shift
  if "$@"; then printf 'OK   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; fail=1; fi
}

# ---- a fake release: a stub binary (no Lisaac compiler needed here) + a real archive ----
# pack.sh names the archive after yaif.li's version, so the fake release has to use the same one.
v=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' yaif.li)
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "yaif %s"\n' "$v" > "$T/bin/yaif"
chmod +x "$T/bin/yaif"

os=linux
case $(uname -m) in x86_64|amd64) arch=x86_64 ;; *) arch=arm64 ;; esac

mkdir -p "$T/srv"
archive_path=$(release/pack.sh "$T/bin/yaif" "$os" "$arch" "$T/srv/out")
archive=$(basename "$archive_path")

# GitHub-shaped layout: /download/<tag>/<file> and a releases-list stand-in for the API.
mkdir -p "$T/srv/download/v$v"
cp "$archive_path" "$T/srv/download/v$v/"
(cd "$T/srv/download/v$v" && sha256sum "$archive" > SHA256SUMS)
printf '<feed><link href="https://github.com/o/r/releases/tag/v%s"/></feed>\n' "$v" > "$T/srv/releases.atom"

port=8765
( cd "$T/srv" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) &
srv_pid=$!
for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$port/releases.atom" >/dev/null 2>&1 && break; sleep 0.1; done

run_install() {  # run_install <home> <install.sh args...>
  local home=$1; shift
  mkdir -p "$home"
  env -i \
    HOME="$home" \
    PATH="/usr/bin:/bin:$home/.cargo/bin" \
    SHELL=/bin/zsh \
    YAIF_TEST_ROOT="$T/root" \
    YAIF_RELEASE_BASE="http://127.0.0.1:$port/download" \
    YAIF_FEED="http://127.0.0.1:$port/releases.atom" \
    bash "$PWD/install.sh" "$@"
}

yaif_lines() {  # yaif_lines <zshrc>: how many lines install.sh added
  # grep -c exits 1 (but still prints "0") when there are zero matches -- don't
  # let that register as a second, spurious "0" via a bare || fallback.
  [ -f "$1" ] || { echo 0; return 0; }
  grep -c '# YAIF' "$1" || true
}

# --- 1: install ---
h1="$T/home1"
# A starter ~/.zshrc, like a real user would have: exercises the "insert fpath
# before oh-my-zsh/compinit" logic instead of trivially skipping it.
mkdir -p "$h1"
cat > "$h1/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
plugins=(git)
source $ZSH/oh-my-zsh.sh
alias ll=ls
EOF
run_install "$h1" --yes --no-plugins --no-heic-hdr > "$T/1.log" 2>&1
check "install: binary"    test -x "$h1/.local/bin/yaif"
check "install: manifest"  test -f "$h1/.local/share/yaif/installed.txt"
check "install: mime type" test -f "$h1/.local/share/mime/packages/yaif.xml"
check "install: completion" test -f "$h1/.local/share/zsh/site-functions/_yaif"
fpath_line=$(grep -n 'site-functions' "$h1/.zshrc" | head -1 | cut -d: -f1)
omz_line=$(grep -n 'oh-my-zsh\.sh' "$h1/.zshrc" | head -1 | cut -d: -f1)
check "install: fpath line before compinit" [ "${fpath_line:-99}" -lt "${omz_line:-0}" ]

# --- 2: re-running doesn't duplicate what it wrote ---
run_install "$h1" --yes --no-plugins --no-heic-hdr > "$T/2.log" 2>&1
check "re-run: no duplicate zshrc lines" [ "$(yaif_lines "$h1/.zshrc")" = 2 ]

# --- 3: uninstall, with the copy of install.sh the install left, removes everything it installed ---
check "install: prints the local uninstall command" grep -qF 'bash ~/.local/share/yaif/install.sh --uninstall' "$T/1.log"
env -i HOME="$h1" PATH=/usr/bin:/bin SHELL=/bin/zsh YAIF_TEST_ROOT="$T/root" \
  bash "$h1/.local/share/yaif/install.sh" --uninstall > "$T/3.log" 2>&1
check "uninstall: its own script gone" [ ! -e "$h1/.local/share/yaif/install.sh" ]
check "uninstall: binary gone"   [ ! -e "$h1/.local/bin/yaif" ]
check "uninstall: manifest gone" [ ! -e "$h1/.local/share/yaif/installed.txt" ]
check "uninstall: rc lines gone" [ "$(yaif_lines "$h1/.zshrc")" = 0 ]
check "uninstall: zshrc otherwise untouched" grep -qF 'alias ll=ls' "$h1/.zshrc"

# --- 4: corrupt archive: refuses to install, nothing left behind ---
h4="$T/home4"
sha=$T/srv/download/v$v/SHA256SUMS
cp "$sha" "$sha.bak"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$archive" > "$sha"
ok4=1
run_install "$h4" --yes --no-plugins --no-heic-hdr > "$T/4.log" 2>&1 || ok4=0
mv "$sha.bak" "$sha"
check "corrupt archive: install refused" [ "$ok4" = 0 ]
check "corrupt archive: nothing installed" [ ! -e "$h4/.local/bin/yaif" ]

# --- 5: --from a local archive, no network ---
h5="$T/home5"
mkdir -p "$h5"
env -i HOME="$h5" PATH=/usr/bin:/bin SHELL=/bin/zsh YAIF_TEST_ROOT="$T/root" \
  bash "$PWD/install.sh" --from "$archive_path" --yes --no-plugins --no-heic-hdr --no-deps > "$T/5.log" 2>&1
check "--from: installs offline" test -x "$h5/.local/bin/yaif"

# --- 5b: run from the unpacked archive: installs those files, downloads nothing ---
h5b="$T/home5b"
mkdir -p "$h5b" "$T/unpacked"
tar -xzf "$archive_path" -C "$T/unpacked"
env -i HOME="$h5b" PATH=/usr/bin:/bin SHELL=/bin/zsh YAIF_TEST_ROOT="$T/root" \
  YAIF_RELEASE_BASE=http://127.0.0.1:1/download YAIF_FEED=http://127.0.0.1:1/releases.atom \
  bash "$T/unpacked/${archive%.tar.gz}/install.sh" --yes --no-plugins --no-heic-hdr --no-deps > "$T/5b.log" 2>&1
check "unpacked archive: installs without downloading" test -x "$h5b/.local/bin/yaif"

# --- 5c: an install of NOVA (YAIF's former name, up to beta.6) is removed by its own uninstaller ---
h5c="$T/home5c"
mkdir -p "$h5c/.local/bin" "$h5c/.local/share/nova"
: > "$h5c/.local/bin/nova"
# A stand-in for NOVA's install.sh (CI checkouts have no old tags): logs its arguments, removes its files.
printf '#!/bin/bash\necho "$@" > "%s/args"\nrm -f "%s/.local/bin/nova" "%s/.local/share/nova/installed.txt"\n' \
  "$h5c" "$h5c" "$h5c" > "$h5c/.local/share/nova/install.sh"
: > "$h5c/.local/share/nova/installed.txt"
: > "$h5c/.zcompdump"
run_install "$h5c" --yes --no-plugins --no-heic-hdr > "$T/5c.log" 2>&1
check "old NOVA: its binary removed"    [ ! -e "$h5c/.local/bin/nova" ]
check "old NOVA: its manifest removed"  [ ! -e "$h5c/.local/share/nova/installed.txt" ]
check "old NOVA: zsh completion cache dropped" [ ! -e "$h5c/.zcompdump" ]
check "old NOVA: uninstalled with the same prefix" grep -qxF -- "--uninstall --prefix $h5c/.local" "$h5c/args"
check "old NOVA: YAIF installed"        test -x "$h5c/.local/bin/yaif"

# --- 6: unknown version fails cleanly, nothing left behind ---
h6="$T/home6"
ok6=1
run_install "$h6" --yes --no-plugins --no-heic-hdr --version 9.9.9 > "$T/6.log" 2>&1 || ok6=0
check "unknown version: install refused" [ "$ok6" = 0 ]
check "unknown version: nothing installed" [ ! -e "$h6/.local/bin/yaif" ]

# --- 7: --help never reads stdin (the curl | bash case: no terminal on fd 0) ---
ok7=1
printf 'not a script\n' | bash "$PWD/install.sh" --help > "$T/7.log" 2>&1 || ok7=0
check "--help: exits cleanly when piped" [ "$ok7" = 1 ]
check "--help: prints usage" grep -q '^Usage:' "$T/7.log"

if [ $fail = 0 ]; then echo "ALL OK"; else echo "see logs above"; fi
exit $fail
