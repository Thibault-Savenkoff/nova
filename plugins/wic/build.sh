#!/bin/bash
# Builds nova_wic.dll (64-bit) with MinGW-w64: sudo dnf install mingw64-gcc-c++
# On Windows, as administrator: regsvr32 nova_wic.dll (regsvr32 /u nova_wic.dll removes it).
cd "$(dirname "$0")" || exit 1
x86_64-w64-mingw32-gcc -std=c99 -O2 -Wall -c ../../libnova/novadec.c -o novadec.o &&
# nova.rc's version: "2.0.0-beta.5" and 2,0,0,5 (the pre-release number last, 0 for a final release).
v=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' ../../nova.li)
printf '#define NOVA_V "%s"\n#define NOVA_V4 %s\n' "$v" "$(printf '%s' "$v" | sed -E 's/^([0-9]+)\.([0-9]+)\.([0-9]+)([^0-9]*([0-9]+))?.*/\1,\2,\3,\5/; s/,$/,0/')" > ../../win/nova_version.h
x86_64-w64-mingw32-windres -DNOVA_DLL -I../../win ../../win/nova.rc -o nova_rc.o &&
x86_64-w64-mingw32-g++ -std=c++17 -O2 -Wall -shared -I../../libnova nova_wic.cpp novadec.o nova_rc.o nova_wic.def -s -o nova_wic.dll \
  -static -static-libgcc -static-libstdc++ -lole32 -lwindowscodecs -lshell32 -luuid &&
rm novadec.o nova_rc.o
