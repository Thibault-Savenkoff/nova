#!/bin/bash
# Builds dist/nova-windows.zip: nova.exe, the WIC codec, zlib and libwebp DLLs (PNG and WebP output), samples.
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-zlib mingw64-libwebp mingw32-nsis msitools
cd "$(dirname "$0")/.." || exit 1
M=/usr/x86_64-w64-mingw32/sys-root/mingw
D=dist/nova-windows
bash win/build.sh && bash plugins/wic/build.sh || exit 1
rm -rf $D dist/nova-windows.zip && mkdir -p $D
cp nova.exe plugins/wic/nova_wic.dll $M/bin/{zlib1,libwebp-7,libsharpyuv-0}.dll docs/samples/{photo,screenshot,animation}.nova completions/nova.ps1 $D/
cp /usr/share/licenses/mingw64-libwebp/COPYING $D/LICENSE-libwebp.txt
sed -n '1,/madler/p' $M/include/zlib.h > $D/LICENSE-zlib.txt
cp LICENSE $D/LICENSE-nova.txt
cat > $D/README.txt <<'EOF'
NOVA for Windows (test build)

1. nova.exe: open a terminal here, then: nova encode photo.jpg photo.nova / nova decode photo.nova photo.jpg
2. Viewer support: right-click install.bat > Run as administrator.
   Then open the .nova files here in Explorer (thumbnails) and Photos.
3. Remove: right-click uninstall.bat > Run as administrator.

zlib1.dll (zlib) and libwebp-7.dll, libsharpyuv-0.dll (libwebp) write PNG and WebP; keep them next to nova.exe.
Their licenses: LICENSE-zlib.txt, LICENSE-libwebp.txt.

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
