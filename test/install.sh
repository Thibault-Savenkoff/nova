#!/bin/bash
# Installs and uninstalls NOVA via install.sh, end to end, against a fake local
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
# pack.sh names the archive after nova.li's version, so the fake release has to use the same one.
v=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' nova.li)
mkdir -p "$T/bin"
printf '#!/bin/sh\necho "nova %s"\n' "$v" > "$T/bin/nova"
chmod +x "$T/bin/nova"

os=linux
case $(uname -m) in x86_64|amd64) arch=x86_64 ;; *) arch=arm64 ;; esac

mkdir -p "$T/srv"
archive_path=$(release/pack.sh "$T/bin/nova" "$os" "$arch" "$T/srv/out")
archive=$(basename "$archive_path")

# GitHub-shaped layout: /download/<tag>/<file> and a releases-list stand-in for the API.
mkdir -p "$T/srv/download/v$v"
cp "$archive_path" "$archive_path.sha256" "$T/srv/download/v$v/"
printf '[{"tag_name": "v%s"}]' "$v" > "$T/srv/api.json"

port=8765
( cd "$T/srv" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1 ) &
srv_pid=$!
for _ in $(seq 1 50); do curl -fsS "http://127.0.0.1:$port/api.json" >/dev/null 2>&1 && break; sleep 0.1; done

run_install() {  # run_install <home> <install.sh args...>
  local home=$1; shift
  mkdir -p "$home"
  env -i \
    HOME="$home" \
    PATH="/usr/bin:/bin:$home/.cargo/bin" \
    SHELL=/bin/zsh \
    NOVA_TEST_ROOT="$T/root" \
    NOVA_RELEASE_BASE="http://127.0.0.1:$port/download" \
    NOVA_API_BASE="http://127.0.0.1:$port/api.json" \
    bash "$PWD/install.sh" "$@"
}

nova_lines() {  # nova_lines <zshrc>: how many lines install.sh added
  # grep -c exits 1 (but still prints "0") when there are zero matches -- don't
  # let that register as a second, spurious "0" via a bare || fallback.
  [ -f "$1" ] || { echo 0; return 0; }
  grep -c '# NOVA' "$1" || true
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
check "install: binary"    test -x "$h1/.local/bin/nova"
check "install: manifest"  test -f "$h1/.local/share/nova/installed.txt"
check "install: mime type" test -f "$h1/.local/share/mime/packages/nova.xml"
check "install: completion" test -f "$h1/.local/share/zsh/site-functions/_nova"
fpath_line=$(grep -n 'site-functions' "$h1/.zshrc" | head -1 | cut -d: -f1)
omz_line=$(grep -n 'oh-my-zsh\.sh' "$h1/.zshrc" | head -1 | cut -d: -f1)
check "install: fpath line before compinit" [ "${fpath_line:-99}" -lt "${omz_line:-0}" ]

# --- 2: re-running doesn't duplicate what it wrote ---
run_install "$h1" --yes --no-plugins --no-heic-hdr > "$T/2.log" 2>&1
check "re-run: no duplicate zshrc lines" [ "$(nova_lines "$h1/.zshrc")" = 2 ]

# --- 3: uninstall removes everything it installed, nothing else ---
env -i HOME="$h1" PATH=/usr/bin:/bin SHELL=/bin/zsh NOVA_TEST_ROOT="$T/root" \
  bash "$PWD/install.sh" --uninstall > "$T/3.log" 2>&1
check "uninstall: binary gone"   [ ! -e "$h1/.local/bin/nova" ]
check "uninstall: manifest gone" [ ! -e "$h1/.local/share/nova/installed.txt" ]
check "uninstall: rc lines gone" [ "$(nova_lines "$h1/.zshrc")" = 0 ]
check "uninstall: zshrc otherwise untouched" grep -qF 'alias ll=ls' "$h1/.zshrc"

# --- 4: corrupt archive: refuses to install, nothing left behind ---
h4="$T/home4"
sha=$T/srv/download/v$v/$archive.sha256
cp "$sha" "$sha.bak"
printf '0000000000000000000000000000000000000000000000000000000000000000  %s\n' "$archive" > "$sha"
ok4=1
run_install "$h4" --yes --no-plugins --no-heic-hdr > "$T/4.log" 2>&1 || ok4=0
mv "$sha.bak" "$sha"
check "corrupt archive: install refused" [ "$ok4" = 0 ]
check "corrupt archive: nothing installed" [ ! -e "$h4/.local/bin/nova" ]

# --- 5: --from a local archive, no network ---
h5="$T/home5"
mkdir -p "$h5"
env -i HOME="$h5" PATH=/usr/bin:/bin SHELL=/bin/zsh NOVA_TEST_ROOT="$T/root" \
  bash "$PWD/install.sh" --from "$archive_path" --yes --no-plugins --no-heic-hdr --no-deps > "$T/5.log" 2>&1
check "--from: installs offline" test -x "$h5/.local/bin/nova"

# --- 6: unknown version fails cleanly, nothing left behind ---
h6="$T/home6"
ok6=1
run_install "$h6" --yes --no-plugins --no-heic-hdr --version 9.9.9 > "$T/6.log" 2>&1 || ok6=0
check "unknown version: install refused" [ "$ok6" = 0 ]
check "unknown version: nothing installed" [ ! -e "$h6/.local/bin/nova" ]

# --- 7: --help never reads stdin (the curl | bash case: no terminal on fd 0) ---
ok7=1
printf 'not a script\n' | bash "$PWD/install.sh" --help > "$T/7.log" 2>&1 || ok7=0
check "--help: exits cleanly when piped" [ "$ok7" = 1 ]
check "--help: prints usage" grep -q '^Usage:' "$T/7.log"

if [ $fail = 0 ]; then echo "ALL OK"; else echo "see logs above"; fi
exit $fail
