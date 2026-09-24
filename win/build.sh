#!/bin/bash
# Builds yaif.exe for Windows (64-bit) with MinGW-w64, from the yaif.c written by `lisaac yaif.li -boost`.
# Fedora: sudo dnf install mingw64-gcc. HEIC, WebP, RAW and PNG output load libheif.dll, libwebp.dll,
# libraw_r.dll and zlib1.dll (or MSYS2's libwebp-7.dll...) when they sit next to yaif.exe or in PATH.
cd "$(dirname "$0")/.." || exit 1
mkdir -p win/sys
for h in win/sys/ioctl.h win/sys/mman.h win/sys/wait.h win/dlfcn.h; do [ -f $h ] || : > $h; done
# yaif.rc's version: "2.0.0-beta.5" and 2,0,0,5 (the pre-release number last, 0 for a final release).
v=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' yaif.li)
printf '#define YAIF_V "%s"\n#define YAIF_V4 %s\n' "$v" "$(printf '%s' "$v" | sed -E 's/^([0-9]+)\.([0-9]+)\.([0-9]+)([^0-9]*([0-9]+))?.*/\1,\2,\3,\5/; s/,$/,0/')" > win/yaif_version.h
x86_64-w64-mingw32-windres win/yaif.rc -o win/yaif_rc.o &&
x86_64-w64-mingw32-gcc -Iwin -include yaif_win.h yaif.c win/yaif_rc.o -O2 -flarge-source-files -w -static -s -lm -o yaif.exe
