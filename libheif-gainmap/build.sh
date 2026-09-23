#!/bin/sh
# Builds libnova-heif: libheif with the gain-map API of its pull request #1503 (pr1503.patch, the
# rebase kept at github.com/fxthomas/libheif, branch pr/1503-gain-maps-v1.23.1; it applies clean on
# 1.23.4), and kvazaar (BSD) as its only codec, linked in statically. nova loads it for one thing:
# writing a .heic that keeps the photo's HDR gain map (ISO 21496-1 `tmap`), which no released
# libheif can do. Everything else, reading HEIC first of all, stays on the system's libheif, which
# gets the distribution's security fixes -- this copy would not. Renamed (nova-heif) so it can
# never be mistaken for the system one, by name or by soname.
#
# Usage: build.sh <work-dir> <output-file>
# The output is one file: a .so, .dylib or .dll, whatever <output-file> is called.
# CMAKE=mingw64-cmake for the Windows cross-build (win/deps.sh). Needs cmake, a C/C++ compiler,
# curl and patch. When #1503 is in a libheif release, this directory goes away.
set -eu

HEIF=1.23.4
HEIF_SHA=d0c02b4b0e978f34a1974b6f3eea7975a537bf7a9195ffeea38e7242ff316fdd
KVAZAAR=2.3.2
KVAZAAR_SHA=b95d2e20f2b0d8d7ed320055740be2e7a730abe28b153b5a788cfca371cc38b2

here=$(cd "$(dirname "$0")" && pwd)
w=$1
out=$2
cmake=${CMAKE:-cmake}
# A bare --parallel is an unbounded make -j: every C++ file of libheif at once, which ran a 8 GB
# machine out of memory. One job per core (JOBS to override).
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}
mkdir -p "$w"

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }
get() {  # get <url> <sha256>
  curl -fsSL -o "$w/src.tar.gz" "$1"
  [ "$(sha "$w/src.tar.gz")" = "$2" ] || { echo "build.sh: SHA-256 mismatch for $1" >&2; exit 1; }
  tar -xzf "$w/src.tar.gz" -C "$w"
  rm -f "$w/src.tar.gz"
}

get "https://github.com/ultravideo/kvazaar/releases/download/v$KVAZAAR/kvazaar-$KVAZAAR.tar.gz" $KVAZAAR_SHA
$cmake -S "$w/kvazaar-$KVAZAAR" -B "$w/b-kvazaar" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$w/kvazaar" \
  -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_TESTS=OFF -DBUILD_KVAZAAR_BINARY=OFF
cmake --build "$w/b-kvazaar" --parallel "$jobs"
cmake --install "$w/b-kvazaar"

get "https://github.com/strukturag/libheif/releases/download/v$HEIF/libheif-$HEIF.tar.gz" $HEIF_SHA
patch -d "$w/libheif-$HEIF" -p1 -s < "$here/pr1503.patch"
# Renamed; and kvazaar is static, which on Windows kvazaar.h must be told (else dllimport).
printf '%s\n' 'set_target_properties(heif PROPERTIES OUTPUT_NAME nova-heif)' \
  'target_compile_definitions(heif PRIVATE KVZ_STATIC_LIB)' >> "$w/libheif-$HEIF/libheif/CMakeLists.txt"
# Every codec off but kvazaar, so nothing else of this system gets linked in.
PKG_CONFIG_PATH="$w/kvazaar/lib/pkgconfig:$w/kvazaar/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
$cmake -S "$w/libheif-$HEIF" -B "$w/b-heif" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
  -DWITH_EXPERIMENTAL_GAIN_MAP=ON -DENABLE_PLUGIN_LOADING=OFF -DWITH_KVAZAAR=ON \
  -DWITH_LIBDE265=OFF -DWITH_X265=OFF -DWITH_X264=OFF -DWITH_OpenH264_DECODER=OFF -DWITH_AOM_DECODER=OFF \
  -DWITH_AOM_ENCODER=OFF -DWITH_DAV1D=OFF -DWITH_SvtEnc=OFF -DWITH_RAV1E=OFF -DWITH_JPEG_DECODER=OFF \
  -DWITH_JPEG_ENCODER=OFF -DWITH_OpenJPEG_DECODER=OFF -DWITH_OpenJPEG_ENCODER=OFF -DWITH_OPENJPH_ENCODER=OFF \
  -DWITH_FFMPEG_DECODER=OFF -DWITH_UVG266=OFF -DWITH_VVDEC=OFF -DWITH_VVENC=OFF -DWITH_LIBSHARPYUV=OFF \
  -DWITH_HEADER_COMPRESSION=OFF -DWITH_EXAMPLES=OFF -DWITH_GDK_PIXBUF=OFF -DBUILD_TESTING=OFF \
  -DBUILD_DOCUMENTATION=OFF
cmake --build "$w/b-heif" --parallel "$jobs" --target heif
lib=$(find "$w/b-heif/libheif" -maxdepth 1 -type f -name 'libnova-heif*' ! -name '*.a' | head -1)
[ -n "$lib" ] || { echo "build.sh: no libnova-heif was built" >&2; exit 1; }
cp "$lib" "$out"
