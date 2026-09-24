#!/bin/bash
# Builds docs/yaif_enc.js + yaif_enc.wasm (yaif for enc_worker.js) from yaif.c, with LibRaw and zlib
# linked in (dl_static.c stands in for dlopen). LibRaw 0.22.2 is fetched and built once into docs/.build;
# it reports errors with C++ exceptions, hence wasm exceptions (Safari 15.2+); SIMD needs Safari 16.4+.
set -e
cd "$(dirname "$0")/.."
source "${EMSDK:-$HOME/emsdk}/emsdk_env.sh" >/dev/null 2>&1
B=docs/.build
LR=$B/LibRaw-0.22.2
if [ ! -f $B/libraw.a ]; then
  mkdir -p $B
  [ -d $LR ] || curl -sfL https://github.com/LibRaw/LibRaw/archive/refs/tags/0.22.2.tar.gz | tar xz -C $B
  mkdir -p $B/o
  ls $LR/src/*.cpp $LR/src/*/*.cpp | grep -v integration | xargs -P "$(nproc)" -I{} sh -c \
    'em++ -O3 -msimd128 -w -fwasm-exceptions -DLIBRAW_NOTHREADS -DUSE_ZLIB -sUSE_ZLIB=1 -I'$LR' -c {} -o '$B'/o/$(echo {} | tr / _).o'
  emar rcs $B/libraw.a $B/o/*.o
fi
emcc yaif.c docs/dl_static.c $B/libraw.a -O3 -msimd128 -w -fwasm-exceptions -sDEFAULT_TO_CXX=1 -Ddlopen=yaif_dlopen -Ddlsym=yaif_dlsym -sUSE_ZLIB=1 \
  -sMODULARIZE=1 -sEXPORT_NAME=YaifWasm -sINVOKE_RUN=0 -sEXIT_RUNTIME=1 \
  -sENVIRONMENT=web,worker,node -sEXPORTED_RUNTIME_METHODS=callMain,FS,ENV \
  -sASYNCIFY=1 -sASYNCIFY_IGNORE_INDIRECT=1 -sASYNCIFY_IMPORTS=np_exchange \
  -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -o docs/yaif_enc.js
