#!/bin/bash
# Builds nova.exe for Windows (64-bit) with MinGW-w64, from the nova.c written by `lisaac nova.li -boost`.
# Fedora: sudo dnf install mingw64-gcc. HEIC, WebP, RAW and PNG output load libheif.dll, libwebp.dll,
# libraw_r.dll and zlib1.dll (or MSYS2's libwebp-7.dll...) when they sit next to nova.exe or in PATH.
cd "$(dirname "$0")/.." || exit 1
mkdir -p win/sys
for h in win/sys/ioctl.h win/sys/mman.h win/sys/wait.h win/dlfcn.h; do [ -f $h ] || : > $h; done
x86_64-w64-mingw32-windres win/nova.rc -o win/nova_rc.o &&
x86_64-w64-mingw32-gcc -Iwin -include nova_win.h nova.c win/nova_rc.o -O2 -flarge-source-files -w -static -s -lm -o nova.exe
