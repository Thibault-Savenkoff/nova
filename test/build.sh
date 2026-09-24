#!/bin/bash
# Exercises build.sh with a fake 'lisaac' (no real compiler needed) and,
# separately, checks it fails cleanly without one. Never touches the real
# $HOME: the final install step runs with HOME redirected under mktemp,
# passed explicitly through env -i.
# build.sh always writes ./yaif and ./yaif.c next to itself (that's the
# documented `lisaac yaif.li -boost` output, gitignored) -- this test cleans
# those up afterward regardless of outcome.
# Run from the repository: test/build.sh
set -eu
cd "$(dirname "$0")/.."

T=$(mktemp -d)
case $T in "${TMPDIR:-/tmp}"/*) ;; *) echo "test/build.sh: unsafe mktemp path: $T" >&2; exit 1 ;; esac

fail=0
cleanup() {
  rm -f -- ./yaif ./yaif.c
  if [ "$fail" = 0 ]; then
    case $T in "${TMPDIR:-/tmp}"/*) rm -rf -- "$T" ;; esac
  else
    echo "logs kept: $T"
  fi
}
trap cleanup EXIT

check() {
  local name=$1; shift
  if "$@"; then printf 'OK   %s\n' "$name"; else printf 'FAIL %s\n' "$name"; fail=1; fi
}

# --- 1: no compiler -> clean failure, nothing built ---
rc=0
env -i PATH=/usr/bin:/bin HOME="$T/home-nolisaac" bash ./build.sh > "$T/1.log" 2>&1 || rc=$?
check "no lisaac: fails" [ "$rc" != 0 ]
check "no lisaac: says so" grep -q 'lisaac' "$T/1.log"
check "no lisaac: built nothing" [ ! -e ./yaif ]

# --- 2: fake lisaac -> compiles (stub) and installs via install.sh ---
mkdir -p "$T/fakebin"
cat > "$T/fakebin/lisaac" <<'EOF'
#!/bin/sh
# Stands in for the real compiler: 'lisaac yaif.li -boost' writes ./yaif.
printf '#!/bin/sh\necho "yaif 2.0.0-beta"\n' > ./yaif
chmod +x ./yaif
: > ./yaif.c
EOF
chmod +x "$T/fakebin/lisaac"

h2="$T/home2"
env -i PATH="$T/fakebin:/usr/bin:/bin" HOME="$h2" YAIF_TEST_ROOT="$T/root" \
  bash ./build.sh --yes --no-plugins > "$T/2.log" 2>&1
check "build+install: yaif binary built" test -x ./yaif
check "build+install: installed" test -x "$h2/.local/bin/yaif"

[ $fail = 0 ] && echo "ALL OK" || echo "see logs above"
exit $fail
