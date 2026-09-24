#!/bin/bash
# Replaces the headers with those of the LibRaw-devel package of this Fedora release.
# Then update the version in README, rebuild yaif and run test/raw.sh.
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
(cd "$T" && dnf download LibRaw-devel && rpm2cpio LibRaw-devel-*.rpm | cpio -idm --quiet)
rm -f libraw/*.h
cp "$T"/usr/include/libraw/*.h libraw/
grep -h "define LIBRAW_M[AI]\w*_VERSION\|define LIBRAW_PATCH_VERSION" libraw/libraw_version.h
