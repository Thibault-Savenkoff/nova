#!/bin/bash
# Cross-compiles, for Windows, the image libraries Fedora has no mingw64 package for.
#
# Phase 1 was HEIC *reading*: libheif with libde265. Phase 2 adds AV1, and one library covers all
# of AVIF: libheif needs aom to read and to write .avif, and libavif needs the same aom for the HDR
# gain map (nova_heic.li loads libavif for that path only). HEVC *encoding* -- writing .heic -- is
# phase 3 and needs kvazaar, not x265: nova is MIT and x265 is GPL.
#
# Usage: win/deps.sh <staging-dir>
# Everything is installed into <staging-dir> and copied from there into the MinGW sysroot, where
# win/dist.sh looks for DLLs like every other one it ships, and where pkg-config finds each library
# for the ones built after it. One marker file per library means a <staging-dir> the CI restored
# from an older key only rebuilds what actually changed -- aom alone is ~10 minutes.
#
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-filesystem mingw64-pkg-config cmake yasm perl
set -eu

AOM=3.13.1
AVIF=1.3.0
DE265=1.1.3
HEIF=1.23.4

stage=${1:?usage: win/deps.sh <staging-dir>}
M=/usr/x86_64-w64-mingw32/sys-root/mingw
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sync()  { [ -d "$stage$M" ] && cp -a "$stage$M/." "$M/" || :; }
built() { [ -e "$stage/.built-$1" ]; }
mark()  { touch "$stage/.built-$1"; echo "win/deps.sh: $1 done"; }
get()   { curl -fsSL "$1" | tar -xz -C "$work"; }
# build <marker> <source-dir> [cmake options...]
build() {
  local name=$1 src=$2
  shift 2
  mingw64-cmake -S "$work/$src" -B "$work/b-$name" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF "$@"
  cmake --build "$work/b-$name" -j"$(nproc)"
  DESTDIR="$stage" cmake --install "$work/b-$name"
  sync
}

# Licences: everything here is LGPL or BSD, and the zip ships the text (win/dist.sh reads it back
# from the sysroot). The README.txt it writes names the versions and upstream URLs, which is what
# relinking one of these needs.
license() {   # license <name> <file>...
  local d="$stage$M/share/licenses/$1"
  shift
  mkdir -p "$d" && cp "$@" "$d/"
}

mkdir -p "$stage"
sync    # whatever the CI cache restored, before anything configures against it

# HEVC decoding, for HEIC. libheif finds it through pkg-config in the sysroot.
if ! built "de265-$DE265"; then
  get "https://github.com/strukturag/libde265/releases/download/v$DE265/libde265-$DE265.tar.gz"
  build "de265-$DE265" "libde265-$DE265" -DENABLE_SDL=OFF
  license libde265 "$work/libde265-$DE265/COPYING"
  mark "de265-$DE265"
fi

# AV1, encoder and decoder: the one library both libheif and libavif need. Shared, so they link
# one copy instead of embedding two. CONFIG_AV1_HIGHBITDEPTH is on by default and has to stay:
# 10-bit is what nova's HDR (PQ) output uses. The rest is build products nobody here runs.
# The assembler is yasm, aom's own default (aom_configure.cmake looks for it first). Not nasm:
# ENABLE_NASM=ON sends aom through test_nasm(), which greps `nasm -hf` for "-Ox" and rejects the
# nasm in fedora:latest outright ("multipass optimization not supported").
if ! built "aom-$AOM"; then
  get "https://storage.googleapis.com/aom-releases/libaom-$AOM.tar.gz"
  build "aom-$AOM" "libaom-$AOM" \
    -DENABLE_EXAMPLES=OFF -DENABLE_TESTS=OFF -DENABLE_TESTDATA=OFF -DENABLE_TOOLS=OFF -DENABLE_DOCS=OFF
  license libaom "$work/libaom-$AOM/LICENSE" "$work/libaom-$AOM/PATENTS"
  mark "aom-$AOM"
fi

# ENABLE_PLUGIN_LOADING=OFF matters: with it on, libheif looks for its codecs as separate plugin
# DLLs at run time, which would each have to be found and shipped. The codecs wanted are compiled
# in: libde265 for HEIC, aom both ways for AVIF. Writing .heic is phase 3 (kvazaar).
if ! built "heif-$HEIF"; then
  get "https://github.com/strukturag/libheif/releases/download/v$HEIF/libheif-$HEIF.tar.gz"
  build "heif-$HEIF" "libheif-$HEIF" \
    -DENABLE_PLUGIN_LOADING=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF \
    -DWITH_LIBDE265=ON -DWITH_AOM_DECODER=ON -DWITH_AOM_ENCODER=ON \
    -DWITH_X265=OFF -DWITH_KVAZAAR=OFF \
    -DWITH_DAV1D=OFF -DWITH_RAV1E=OFF -DWITH_SvtEnc=OFF \
    -DWITH_JPEG_DECODER=OFF -DWITH_JPEG_ENCODER=OFF \
    -DWITH_OpenJPEG_DECODER=OFF -DWITH_OpenJPEG_ENCODER=OFF \
    -DWITH_UNCOMPRESSED_CODEC=OFF
  license libheif "$work/libheif-$HEIF/COPYING"
  mark "heif-$HEIF"
fi

# Only nova's HDR gain-map AVIF goes through libavif (nova_heic.li dlopens "libavif.so.16", which
# win/nova_win.h turns into libavif-16.dll); plain AVIF is libheif's job. 1.3.0 is the version
# nova_heic.li checked its struct offsets against, and it has the gain-map API unconditionally.
if ! built "avif-$AVIF"; then
  get "https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$AVIF.tar.gz"
  build "avif-$AVIF" "libavif-$AVIF" \
    -DAVIF_CODEC_AOM=SYSTEM -DAVIF_LIBYUV=OFF -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF
  license libavif "$work/libavif-$AVIF/LICENSE"
  mark "avif-$AVIF"
fi

echo "win/deps.sh: installed into $M"
