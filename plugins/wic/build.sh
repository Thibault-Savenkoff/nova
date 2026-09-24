#!/bin/bash
# Builds yaif_wic.dll (64-bit) with MinGW-w64: sudo dnf install mingw64-gcc-c++
# On Windows, as administrator: regsvr32 yaif_wic.dll (regsvr32 /u yaif_wic.dll removes it).
cd "$(dirname "$0")" || exit 1
x86_64-w64-mingw32-gcc -std=c99 -O2 -Wall -c ../../libyaif/yaifdec.c -o yaifdec.o &&
# yaif.rc's version: "2.0.0-beta.5" and 2,0,0,5 (the pre-release number last, 0 for a final release).
v=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' ../../yaif.li)
printf '#define YAIF_V "%s"\n#define YAIF_V4 %s\n' "$v" "$(printf '%s' "$v" | sed -E 's/^([0-9]+)\.([0-9]+)\.([0-9]+)([^0-9]*([0-9]+))?.*/\1,\2,\3,\5/; s/,$/,0/')" > ../../win/yaif_version.h
x86_64-w64-mingw32-windres -DYAIF_DLL -I../../win ../../win/yaif.rc -o yaif_rc.o &&
x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -shared -I../../libyaif yaif_wic.cpp yaifdec.o yaif_rc.o yaif_wic.def -s -o yaif_wic.dll \
  -static -static-libgcc -static-libstdc++ -lole32 -lwindowscodecs -lshell32 -luuid &&
rm yaifdec.o yaif_rc.o
