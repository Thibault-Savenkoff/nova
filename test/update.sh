#!/bin/bash
# The update check (nova_update.li): once a day, in a terminal only, never blocking.
# A fake curl stands in for GitHub (no network), and script(1) gives nova a terminal.
# Run from nova-lisaac/ after building ./nova: test/update.sh
set -eu
cd "$(dirname "$0")/.."
[ -x ./nova ] || { echo "build ./nova first (lisaac nova.li -boost)"; exit 1; }

T=$(mktemp -d)
case $T in "${TMPDIR:-/tmp}"/*) ;; *) echo "unsafe mktemp path: $T" >&2; exit 1 ;; esac
trap 'rm -rf -- "$T"' EXIT
fail=0
check() {
  local name=$1; shift
  if "$@"; then printf 'OK   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; fail=1; fi
}
no() { ! grep -q "$@"; }

# Fake curl: logs its call, writes the release list given in $T/list to its -o file.
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<EOF
#!/bin/sh
echo call >> "$T/calls"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && out=\$2; shift; done
cp "$T/list" "\$out"
EOF
chmod +x "$T/bin/curl"
cache="$T/cache/nova/releases.json"

# run [env...]: ./nova --version in a terminal, with its stderr (the notice) in $T/out
run() {
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" XDG_CACHE_HOME="$T/cache" "$@" \
    script -qec "$PWD/nova --version; sleep 0.5" /dev/null > "$T/out" 2>&1
  # (the sleep keeps the terminal open while the background curl runs, as a real one stays)
}
calls() { [ -f "$T/calls" ] && wc -l < "$T/calls" || echo 0; }

printf '[{"tag_name": "v2.1.0"}, {"tag_name": "v1.9.9"}, {"tag_name": "v2.0.0"}]' > "$T/list"

# --- no terminal: nothing at all ---
env -i PATH="$T/bin:/usr/bin:/bin" HOME="$T/home" XDG_CACHE_HOME="$T/cache" ./nova --version > "$T/out" 2>&1
sleep 0.3
check "no terminal: no check" [ "$(calls)" = 0 ]
check "no terminal: no cache" [ ! -e "$cache" ]

# --- first run: no cache yet, so no notice, but a background refresh ---
run
check "first run: no notice" no available "$T/out"
check "first run: one refresh" [ "$(calls)" = 1 ]
check "first run: cache written" grep -q v2.1.0 "$cache"

# --- next run, same day: notice from the cache, no new refresh ---
run
check "same day: notice" grep -q 'nova 2.1.0 is available (this is 2.0.0-beta)' "$T/out"
check "same day: no refresh" [ "$(calls)" = 1 ]
check "same day: stdout untouched" grep -q '^nova 2.0.0-beta' "$T/out"

# --- turned off ---
run NOVA_NO_UPDATE_CHECK=1
check "NOVA_NO_UPDATE_CHECK=1: no notice" no available "$T/out"

# --- a day later: refreshed again; the release of this beta is newer than it ---
printf '[{"tag_name": "v2.0.0"}, {"tag_name": "v3.0.0"}]' > "$T/list"
touch -d '2 days ago' "$cache"
run
check "a day later: refresh" [ "$(calls)" = 2 ]
run
check "2.0.0 > 2.0.0-beta, other major ignored" grep -q 'nova 2.0.0 is available' "$T/out"

# --- nothing newer: no notice ---
printf '[{"tag_name": "v2.0.0-alpha"}, {"tag_name": "v1.1.8"}]' > "$T/list"
touch -d '2 days ago' "$cache"
run; run
check "older only: no notice" no available "$T/out"

# --- a failed refresh keeps the old cache ---
printf 'exit 22\n' > "$T/bin/curl"
touch -d '2 days ago' "$cache"
run
check "failed refresh: cache kept" grep -q v2.0.0-alpha "$cache"

[ $fail = 0 ] && echo "ALL OK"
exit $fail
