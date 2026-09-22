#!/bin/bash
# Builds dist/nova-windows.zip: nova.exe, the WIC codec, zlib and libwebp DLLs (PNG and WebP output), samples.
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-zlib mingw64-libwebp mingw64-LibRaw mingw32-nsis msitools
# libheif/libde265 have no mingw64 package: run win/deps.sh once before this script.
cd "$(dirname "$0")/.." || exit 1
M=/usr/x86_64-w64-mingw32/sys-root/mingw
D=dist/nova-windows
bash win/build.sh && bash plugins/wic/build.sh || exit 1
rm -rf $D dist/nova-windows.zip && mkdir -p $D
cp nova.exe plugins/wic/nova_wic.dll $M/bin/{zlib1,libwebp-7,libsharpyuv-0}.dll docs/samples/{photo,screenshot,animation}.nova $D/
# Not "nova.ps1": this folder goes on the PATH, and PowerShell resolves a bare `nova` to a .ps1
# there in preference to nova.exe -- the command then silently does nothing at all.
cp completions/nova.ps1 $D/nova-completion.ps1
# Camera RAW: nova dlopens libraw_r.so.25, which win/nova_win.h turns into libraw_r-25.dll.
# The other three are LibRaw's own DLL dependencies inside the MinGW sysroot, from
# `objdump -p` on it: without them LoadLibrary fails and RAW is silently unavailable.
cp $M/bin/libraw_r-*.dll $M/bin/{libgcc_s_seh-1,liblcms2-2,libstdc++-6,libwinpthread-1}.dll $D/
# HEIC reading: libheif and its HEVC decoder, cross-compiled by win/deps.sh because Fedora has no
# mingw64 package for either. Writing .heic and reading/writing AVIF still need more (see deps.sh).
cp $M/bin/libheif*.dll $M/bin/libde265*.dll $D/
# Fedora ships its MinGW DLLs unstripped: libstdc++-6.dll alone is 29 MB of debug
# symbols nobody here can use, five times the rest of the package put together.
x86_64-w64-mingw32-strip $D/*.dll

# Ship nothing that cannot load: every DLL here is asked what it imports, and any import that is
# one of ours (it exists in the MinGW sysroot) has to be in the package too. A missing
# libwinpthread-1.dll -- pulled in by libgcc and libstdc++, so LibRaw failed with a bare
# ERROR_MOD_NOT_FOUND and no hint of which file was absent -- is what this check is for.
missing=$(for d in $D/*.dll; do x86_64-w64-mingw32-objdump -p "$d" | sed -n 's/.*DLL Name: //p'; done |
          tr -d '\r' | sort -u |
          while read -r n; do [ -f "$M/bin/$n" ] && [ ! -f "$D/$n" ] && echo "$n"; done)
[ -z "$missing" ] || { echo "win/dist.sh: DLLs imported but not packaged:" $missing >&2; exit 1; }
cp /usr/share/licenses/mingw64-libwebp/COPYING $D/LICENSE-libwebp.txt
cat /usr/share/licenses/mingw64-LibRaw/{COPYRIGHT,LICENSE.LGPL} > $D/LICENSE-libraw.txt
cp $M/share/licenses/libheif/COPYING $D/LICENSE-libheif.txt
cp $M/share/licenses/libde265/COPYING $D/LICENSE-libde265.txt
sed -n '1,/madler/p' $M/include/zlib.h > $D/LICENSE-zlib.txt
cp LICENSE $D/LICENSE-nova.txt
cat > $D/README.txt <<'EOF'
NOVA for Windows (test build)

0. Windows marks everything extracted from a downloaded zip, which makes PowerShell refuse to run
   nova-completion.ps1. Clear it once, in PowerShell, from this folder:
       Get-ChildItem -Recurse | Unblock-File
   Ticking "Unblock" in the zip's Properties before extracting does the same for every file at once.

1. nova.exe: open a terminal here, then: nova encode photo.jpg photo.nova / nova decode photo.nova photo.jpg
2. Viewer support: double-click install.bat (it asks for administrator rights itself).
   Then open the .nova files here in Explorer (thumbnails) and Windows Photo Viewer. The modern
   Photos app takes no third-party codec, whatever the format -- it will not open .nova.
3. Remove: double-click uninstall.bat.

zlib1.dll (zlib) and libwebp-7.dll, libsharpyuv-0.dll (libwebp) write PNG and WebP; libraw_r-25.dll
(LibRaw) with libgcc_s_seh-1.dll, liblcms2-2.dll and libstdc++-6.dll read camera RAW files. Keep them
all next to nova.exe. Their licenses: LICENSE-zlib.txt, LICENSE-libwebp.txt, LICENSE-libraw.txt.

Reading .heic works: libheif.dll with libde265.dll, both LGPL, built unmodified from
  https://github.com/strukturag/libheif    v1.23.4
  https://github.com/strukturag/libde265   v1.1.3
Their licence is LICENSE-libheif.txt and LICENSE-libde265.txt; replacing either DLL with your own
build of the same version is all that is needed to relink.

Writing .heic, and AVIF either way, do not work yet: they need an HEVC encoder and libavif, which
are not in this package.

4. Tab completion, PowerShell only (cmd.exe has no such hook for a third-party program). Run once:
       .\nova-profile.ps1
   It adds one line to your PowerShell profile; .\nova-profile.ps1 -Remove takes it back out.
EOF
# DllRegisterServer writes to HKEY_CLASSES_ROOT and HKLM, so without elevation regsvr32 fails with
# 0x80040201 (SELFREG_E_CLASS) and nothing says why. `net session` is the usual test: it needs
# administrator rights and nothing else. Relaunch elevated rather than make the user know to.
for f in install uninstall; do
  [ $f = install ] && flags="" || flags="/u "
  cat > $D/$f.bat <<EOF
@echo off
cd /d "%~dp0"
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
regsvr32 $flags nova_wic.dll
EOF
done
# PowerShell has no auto-load directory for argument completers, so the only way to make the
# completion permanent is a line in the user's $PROFILE. PowerShell edits its own file here:
# doing it from NSIS would mean guessing the profile's encoding. Idempotent both ways, so a
# reinstall cannot double the line, and it never rewrites the file just to add to it.
cat > $D/nova-profile.ps1 <<'EOF'
# Adds (or, with -Remove, takes out) the line that loads NOVA's tab completion, in your PowerShell
# profile. Run it once: .\nova-profile.ps1
param([switch]$Remove, [string]$Script = "$PSScriptRoot\nova-completion.ps1", [switch]$ThisHostOnly)
$line = ". `"$Script`""
if (-not (Test-Path $PROFILE)) {
    if ($Remove) { return }
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$lines = @(Get-Content -LiteralPath $PROFILE)
$ours  = @($lines | Where-Object { $_ -match 'nova-completion\.ps1' })
# Adding appends instead of rewriting: Set-Content re-encodes the whole file, and Windows
# PowerShell 5.1 -- the one both installers call -- writes ANSI by default, which would mangle
# the accented characters of a UTF-8 profile the user owns. Only removing a line we put there
# before (an uninstall, or a reinstall into another directory) rewrites, and then it has to.
if ($Remove) {
    if ($ours) { Set-Content -LiteralPath $PROFILE -Value @($lines | Where-Object { $_ -notmatch 'nova-completion\.ps1' }) }
} elseif ($lines -notcontains $line) {
    if ($ours) { Set-Content -LiteralPath $PROFILE -Value @($lines | Where-Object { $_ -notmatch 'nova-completion\.ps1' }) }
    # A profile whose last line has no newline would otherwise get ours glued onto it.
    $raw = [IO.File]::ReadAllText($PROFILE)
    if ($raw -and $raw[-1] -notin "`n", "`r") { [IO.File]::AppendAllText($PROFILE, [Environment]::NewLine) }
    Add-Content -LiteralPath $PROFILE -Value $line
}

# $PROFILE is per host: Windows PowerShell 5.1 and PowerShell 7 read different files, and the
# installers only ever call 5.1. Hand the script to the other one as well, if it is installed;
# -ThisHostOnly is what stops that from bouncing back.
if (-not $ThisHostOnly) {
    $other = if ($PSVersionTable.PSVersion.Major -ge 6) { 'powershell.exe' } else { 'pwsh.exe' }
    $exe = Get-Command $other -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Script', $Script, '-ThisHostOnly')
        if ($Remove) { $a += '-Remove' }
        & $exe.Source @a
    }
}
EOF
sed -i 's/$/\r/' $D/README.txt $D/LICENSE-*.txt $D/nova-completion.ps1 $D/nova-profile.ps1 $D/install.bat $D/uninstall.bat
(cd dist && zip -qr nova-windows.zip nova-windows) && ls -l dist/nova-windows.zip
# Installer (sudo dnf install mingw32-nsis): dist/nova-setup.exe
if command -v makensis >/dev/null; then makensis -V2 win/nova.nsi && ls -l dist/nova-setup.exe; else echo "makensis missing: no nova-setup.exe"; fi
# MSI (sudo dnf install msitools): dist/nova-setup.msi
if command -v wixl >/dev/null; then wixl -a x64 -o dist/nova-setup.msi win/nova.wxs && ls -l dist/nova-setup.msi; else echo "wixl missing: no nova-setup.msi"; fi
