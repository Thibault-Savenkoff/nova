#!/usr/bin/env bash
# Compile LibRaw to WebAssembly.
# Requires: emcc (Emscripten), curl, tar, make.
# Run from the repo root:  bash wasm/build.sh
set -euo pipefail

LIBRAW_VER="0.21.3"
LIBRAW_URL="https://www.libraw.org/data/LibRaw-${LIBRAW_VER}.tar.gz"
WASM_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/.." && pwd)"
DOCS_DIR="${REPO_ROOT}/docs"
BUILD_DIR="${WASM_DIR}/.build"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# ── Download LibRaw ────────────────────────────────────────────────────────────
if [ ! -d "LibRaw-${LIBRAW_VER}" ]; then
    echo "→ Downloading LibRaw ${LIBRAW_VER}…"
    curl -sL "${LIBRAW_URL}" | tar xz
fi

# ── Configure with Emscripten ─────────────────────────────────────────────────
echo "→ Configuring LibRaw with emconfigure…"
cd "LibRaw-${LIBRAW_VER}"

# Only reconfigure if Makefile is missing or stale
if [ ! -f "Makefile" ] || [ "configure" -nt "Makefile" ]; then
    emconfigure ./configure \
        --disable-shared \
        --disable-examples \
        --disable-jasper \
        --disable-jpeg \
        --disable-lcms \
        CXXFLAGS="-O3 -DLIBRAW_NOTHREADS"
fi

echo "→ Building LibRaw…"
emmake make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

cd "${BUILD_DIR}"

# ── Link wrapper → WASM ───────────────────────────────────────────────────────
echo "→ Compiling WASM wrapper…"
emcc "${WASM_DIR}/libraw_wrapper.cpp" \
    -I "LibRaw-${LIBRAW_VER}" \
    -L "LibRaw-${LIBRAW_VER}/lib/.libs" -lraw_r \
    -o "${DOCS_DIR}/libraw.js" \
    -s WASM=1 \
    -s EXPORT_NAME=LibRawModule \
    -s MODULARIZE=1 \
    -s EXPORTED_FUNCTIONS='["_libraw_decode","_libraw_free","_malloc","_free"]' \
    -s EXPORTED_RUNTIME_METHODS='["HEAPU8","HEAPU16","getValue","setValue"]' \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s MAXIMUM_MEMORY=2gb \
    -s ENVIRONMENT=web \
    -s SINGLE_FILE=0 \
    -O3

echo "✓ Generated:"
echo "  ${DOCS_DIR}/libraw.js   ($(wc -c < "${DOCS_DIR}/libraw.js" | tr -d ' ') bytes)"
echo "  ${DOCS_DIR}/libraw.wasm ($(wc -c < "${DOCS_DIR}/libraw.wasm" | tr -d ' ') bytes)"
