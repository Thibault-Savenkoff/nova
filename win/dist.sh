#!/bin/bash
# Builds dist/nova-windows.zip: nova.exe, the WIC codec, zlib and libwebp DLLs (PNG and WebP output), samples.
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-zlib mingw64-libwebp mingw64-LibRaw mingw32-nsis msitools
cd "$(dirname "$0")/.." || exit 1
M=/usr/x86_64-w64-mingw32/sys-root/mingw
D=dist/nova-windows
bash win/build.sh && bash plugins/wic/build.sh || exit 1
rm -rf $D dist/nova-windows.zip && mkdir -p $D
cp nova.exe plugins/wic/nova_wic.dll $M/bin/{zlib1,libwebp-7,libsharpyuv-0}.dll docs/samples/{photo,screenshot,animation}.nova completions/nova.ps1 $D/
# Camera RAW: nova dlopens libraw_r.so.25, which win/nova_win.h turns into libraw_r-25.dll.
# The other three are LibRaw's own DLL dependencies inside the MinGW sysroot, from
# `objdump -p` on it: without them LoadLibrary fails and RAW is silently unavailable.
cp $M/bin/libraw_r-*.dll $M/bin/{libgcc_s_seh-1,liblcms2-2,libstdc++-6}.dll $D/
# Fedora ships its MinGW DLLs unstripped: libstdc++-6.dll alone is 29 MB of debug
# symbols nobody here can use, five times the rest of the package put together.
x86_64-w64-mingw32-strip $D/*.dll
cp /usr/share/licenses/mingw64-libwebp/COPYING $D/LICENSE-libwebp.txt
cat /usr/share/licenses/mingw64-LibRaw/{COPYRIGHT,LICENSE.LGPL} > $D/LICENSE-libraw.txt
sed -n '1,/madler/p' $M/include/zlib.h > $D/LICENSE-zlib.txt
cp LICENSE $D/LICENSE-nova.txt
cat > $D/README.txt <<'EOF'
NOVA for Windows (test build)

1. nova.exe: open a terminal here, then: nova encode photo.jpg photo.nova / nova decode photo.nova photo.jpg
2. Viewer support: right-click install.bat > Run as administrator.
   Then open the .nova files here in Explorer (thumbnails) and Windows Photo Viewer. The modern
   Photos app takes no third-party codec, whatever the format -- it will not open .nova.
3. Remove: right-click uninstall.bat > Run as administrator.

zlib1.dll (zlib) and libwebp-7.dll, libsharpyuv-0.dll (libwebp) write PNG and WebP; libraw_r-25.dll
(LibRaw) with libgcc_s_seh-1.dll, liblcms2-2.dll and libstdc++-6.dll read camera RAW files. Keep them
all next to nova.exe. Their licenses: LICENSE-zlib.txt, LICENSE-libwebp.txt, LICENSE-libraw.txt.

HEIC and AVIF are not available in this build: nova loads libheif at run time and there is no MinGW
build of it to ship. Put libheif.dll next to nova.exe yourself and they start working.

4. Tab completion, PowerShell only (cmd.exe has no such hook for a third-party program): add to your
   $PROFILE (not done automatically): . "C:\path\to\nova.ps1"
EOF
printf '@echo off\r\ncd /d "%%~dp0"\r\nregsvr32 nova_wic.dll\r\n' > $D/install.bat
printf '@echo off\r\ncd /d "%%~dp0"\r\nregsvr32 /u nova_wic.dll\r\n' > $D/uninstall.bat
sed -i 's/$/\r/' $D/README.txt $D/LICENSE-*.txt $D/nova.ps1
(cd dist && zip -qr nova-windows.zip nova-windows) && ls -l dist/nova-windows.zip
# Installer (sudo dnf install mingw32-nsis): dist/nova-setup.exe
if command -v makensis >/dev/null; then makensis -V2 win/nova.nsi && ls -l dist/nova-setup.exe; else echo "makensis missing: no nova-setup.exe"; fi
# MSI (sudo dnf install msitools): dist/nova-setup.msi
if command -v wixl >/dev/null; then wixl -a x64 -o dist/nova-setup.msi win/nova.wxs && ls -l dist/nova-setup.msi; else echo "wixl missing: no nova-setup.msi"; fi
