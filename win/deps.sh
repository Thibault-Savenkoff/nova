#!/bin/bash
# Cross-compiles, for Windows, the libraries Fedora has no mingw64 package for. Phase 1 is HEIC
# *reading*: libheif with libde265 only. HEVC encoding (kvazaar, not x265: nova is MIT and x265 is
# GPL) and AVIF (libavif + aom) are their own phases and are switched off here.
#
# Usage: win/deps.sh <staging-dir>
# The build installs into <staging-dir> and is then copied into the MinGW sysroot, where
# win/dist.sh looks for DLLs like every other one it ships. A populated <staging-dir> is reused as
# is, so CI can cache it and pay the build once (see .github/workflows/release.yml).
#
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-filesystem mingw64-pkg-config cmake
set -eu

DE265=1.1.3
HEIF=1.23.4

stage=${1:?usage: win/deps.sh <staging-dir>}
M=/usr/x86_64-w64-mingw32/sys-root/mingw

install_stage() {
  cp -a "$stage$M/." "$M/"
  echo "win/deps.sh: installed into $M"
}

# Cache hit: the tree is already built, nothing to do but put it in place.
if [ -d "$stage$M/bin" ]; then install_stage; exit 0; fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

get() { curl -fsSL "$1" | tar -xz -C "$work"; }
get "https://github.com/strukturag/libde265/releases/download/v$DE265/libde265-$DE265.tar.gz"
get "https://github.com/strukturag/libheif/releases/download/v$HEIF/libheif-$HEIF.tar.gz"

# The decoder first: libheif finds it through pkg-config in the sysroot, so it is installed for
# real (not just staged) before libheif is configured.
mingw64-cmake -S "$work/libde265-$DE265" -B "$work/b-de265" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DENABLE_SDL=OFF -DBUILD_TESTING=OFF
cmake --build "$work/b-de265" -j"$(nproc)"
DESTDIR="$stage" cmake --install "$work/b-de265"
cp -a "$stage$M/." "$M/"

# Decode only. ENABLE_PLUGIN_LOADING=OFF matters: with it on, libheif looks for codec plugins as
# separate DLLs at run time, which would have to be found and shipped too.
mingw64-cmake -S "$work/libheif-$HEIF" -B "$work/b-heif" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=OFF \
  -DENABLE_PLUGIN_LOADING=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF \
  -DWITH_LIBDE265=ON \
  -DWITH_X265=OFF -DWITH_KVAZAAR=OFF -DWITH_AOM_DECODER=OFF -DWITH_AOM_ENCODER=OFF \
  -DWITH_DAV1D=OFF -DWITH_RAV1E=OFF -DWITH_SvtEnc=OFF \
  -DWITH_JPEG_DECODER=OFF -DWITH_JPEG_ENCODER=OFF \
  -DWITH_OpenJPEG_DECODER=OFF -DWITH_OpenJPEG_ENCODER=OFF \
  -DWITH_UNCOMPRESSED_CODEC=OFF
cmake --build "$work/b-heif" -j"$(nproc)"
DESTDIR="$stage" cmake --install "$work/b-heif"
install_stage
