#!/bin/bash
# Runs every test script with its default files and prints one line each: OK, or FAIL with the
# log to read. A script fails on a non-zero exit or a FAIL / ROUND TRIP FAILED / DIFF line.
# rd_summary.sh (size measures, no check) is left out. Takes ~25 min (raw.sh and js.sh are long).
# Run from the repository: test/all.sh [script names...], e.g. test/all.sh lossy meta
cd "$(dirname "$0")/.." || exit 1
L=$(mktemp -d)
names=("$@")
[ ${#names[@]} -eq 0 ] && names=(check anim lossy preview meta tiff jpeg webp heif hdr raw js libnova_unit unit replicas update)
fail=0
for n in "${names[@]}"; do
  t0=$(date +%s)
  bash "test/$n.sh" > "$L/$n.log" 2>&1
  code=$?
  dt=$(( $(date +%s) - t0 ))
  if [ $code -ne 0 ] || grep -qE 'FAIL|DIFF|differ' "$L/$n.log"; then
    printf 'FAIL %-9s %4d s  log: %s\n' "$n" "$dt" "$L/$n.log"
    fail=1
  else
    printf 'OK   %-9s %4d s\n' "$n" "$dt"
  fi
done
[ $fail -eq 0 ] && rm -rf "$L"
exit $fail
