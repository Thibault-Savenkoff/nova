#!/bin/bash
# Builds dist/yaif-<version>-windows-x86_64{.zip,-setup.exe,.msi}: yaif.exe, the WIC codec, zlib and libwebp DLLs (PNG and WebP output), samples.
# Fedora: sudo dnf install mingw64-gcc-c++ mingw64-zlib mingw64-libwebp mingw64-LibRaw mingw32-nsis msitools
# libheif/libde265 have no mingw64 package: run win/deps.sh once before this script.
cd "$(dirname "$0")/.." || exit 1
M=/usr/x86_64-w64-mingw32/sys-root/mingw
D=dist/yaif-windows
bash win/build.sh && bash plugins/wic/build.sh || exit 1
rm -rf $D dist/yaif-windows.zip && mkdir -p $D
cp yaif.exe plugins/wic/yaif_wic.dll $M/bin/{zlib1,libwebp-7,libsharpyuv-0}.dll docs/samples/{photo,screenshot,animation}.yaif $D/
# Not "yaif.ps1": this folder goes on the PATH, and PowerShell resolves a bare `yaif` to a .ps1
# there in preference to yaif.exe -- the command then silently does nothing at all.
cp completions/yaif.ps1 $D/yaif-completion.ps1
# Camera RAW: yaif dlopens libraw_r.so.25, which win/yaif_win.h turns into libraw_r-25.dll.
# The other three are LibRaw's own DLL dependencies inside the MinGW sysroot, from
# `objdump -p` on it: without them LoadLibrary fails and RAW is silently unavailable.
cp $M/bin/libraw_r-*.dll $M/bin/{libgcc_s_seh-1,liblcms2-2,libstdc++-6,libwinpthread-1}.dll $D/
# HEIC both ways (libheif with libde265 and kvazaar) and AVIF both ways (aom, plus libavif for the
# HDR gain map), all cross-compiled by win/deps.sh because Fedora packages none of them for mingw64.
cp $M/bin/libheif*.dll $M/bin/libde265*.dll $M/bin/libkvazaar*.dll $M/bin/libaom*.dll $M/bin/libavif*.dll $M/bin/libyaif-heif.dll $D/
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

# win/yaif.nsi globs *.dll, but win/yaif.wxs lists its files one by one and wixl does not complain
# about one that is not there -- the MSI silently shipped without libheif that way. Same failure,
# loud now.
unlisted=$(for d in $D/*.dll; do grep -q "yaif-windows/$(basename $d)\"" win/yaif.wxs || basename $d; done)
[ -z "$unlisted" ] || { echo "win/dist.sh: DLLs packaged but absent from win/yaif.wxs:" $unlisted >&2; exit 1; }
cp /usr/share/licenses/mingw64-libwebp/COPYING $D/LICENSE-libwebp.txt
cat /usr/share/licenses/mingw64-LibRaw/{COPYRIGHT,LICENSE.LGPL} > $D/LICENSE-libraw.txt
cp $M/share/licenses/libheif/COPYING $D/LICENSE-libheif.txt
cp $M/share/licenses/libde265/COPYING $D/LICENSE-libde265.txt
cat $M/share/licenses/libaom/{LICENSE,PATENTS} > $D/LICENSE-libaom.txt
cp $M/share/licenses/libavif/LICENSE $D/LICENSE-libavif.txt
cp $M/share/licenses/kvazaar/LICENSE $D/LICENSE-kvazaar.txt
sed -n '1,/madler/p' $M/include/zlib.h > $D/LICENSE-zlib.txt
cp LICENSE $D/LICENSE-yaif.txt
cat > $D/README.txt <<'EOF'
YAIF for Windows (test build)

0. Windows marks everything extracted from a downloaded zip, which makes PowerShell refuse to run
   yaif-completion.ps1. Clear it once, in PowerShell, from this folder:
       Get-ChildItem -Recurse | Unblock-File
   Ticking "Unblock" in the zip's Properties before extracting does the same for every file at once.

1. yaif.exe: open a terminal here, then: yaif encode photo.jpg photo.yaif / yaif decode photo.yaif photo.jpg
2. Viewer support: double-click install.bat (it asks for administrator rights itself).
   Then open the .yaif files here in Explorer (thumbnails) and Windows Photo Viewer. The modern
   Photos app takes no third-party codec, whatever the format -- it will not open .yaif.
3. Remove: double-click uninstall.bat.

zlib1.dll (zlib) and libwebp-7.dll, libsharpyuv-0.dll (libwebp) write PNG and WebP; libraw_r-25.dll
(LibRaw) with libgcc_s_seh-1.dll, liblcms2-2.dll and libstdc++-6.dll read camera RAW files. Keep them
all next to yaif.exe. Their licenses: LICENSE-zlib.txt, LICENSE-libwebp.txt, LICENSE-libraw.txt.

HEIC and AVIF work, reading and writing. Those DLLs are built unmodified from:
  https://github.com/strukturag/libheif    v1.23.4    LGPL    LICENSE-libheif.txt
  https://github.com/strukturag/libde265   v1.1.3     LGPL    LICENSE-libde265.txt
  https://aomedia.googlesource.com/aom     v3.13.1    BSD     LICENSE-libaom.txt
  https://github.com/AOMediaCodec/libavif  v1.3.0     BSD     LICENSE-libavif.txt
  https://github.com/ultravideo/kvazaar    v2.3.2     BSD     LICENSE-kvazaar.txt
Replacing one with your own build of the same version is all that is needed to relink.
libyaif-heif.dll is libheif v1.23.4 with a change of its own: its gain-map pull request (#1503),
which no libheif release has yet, and kvazaar built in. yaif uses it only to write a .heic that keeps
a photo's HDR. The change and the build recipe: libheif-gainmap/ in yaif's source,
https://github.com/Thibault-Savenkoff/yaif/tree/v2/libheif-gainmap

4. Tab completion, PowerShell only (cmd.exe has no such hook for a third-party program). Run once:
       .\yaif-profile.ps1
   It adds one line to your PowerShell profile; .\yaif-profile.ps1 -Remove takes it back out.
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
regsvr32 $flags yaif_wic.dll
EOF
done
# PowerShell has no auto-load directory for argument completers, so the only way to make the
# completion permanent is a line in the user's $PROFILE. PowerShell edits its own file here:
# doing it from NSIS would mean guessing the profile's encoding. Idempotent both ways, so a
# reinstall cannot double the line, and it never rewrites the file just to add to it.
cat > $D/yaif-profile.ps1 <<'EOF'
# Adds (or, with -Remove, takes out) the line that loads YAIF's tab completion, in your PowerShell
# profile. Run it once: .\yaif-profile.ps1
param([switch]$Remove, [string]$Script = "$PSScriptRoot\yaif-completion.ps1", [switch]$ThisHostOnly)
$line = ". `"$Script`""
if (-not (Test-Path $PROFILE)) {
    if ($Remove) { return }
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$lines = @(Get-Content -LiteralPath $PROFILE)
$ours  = @($lines | Where-Object { $_ -match 'yaif-completion\.ps1' })
# Adding appends instead of rewriting: Set-Content re-encodes the whole file, and Windows
# PowerShell 5.1 -- the one both installers call -- writes ANSI by default, which would mangle
# the accented characters of a UTF-8 profile the user owns. Only removing a line we put there
# before (an uninstall, or a reinstall into another directory) rewrites, and then it has to.
if ($Remove) {
    if ($ours) { Set-Content -LiteralPath $PROFILE -Value @($lines | Where-Object { $_ -notmatch 'yaif-completion\.ps1' }) }
} elseif ($lines -notcontains $line) {
    if ($ours) { Set-Content -LiteralPath $PROFILE -Value @($lines | Where-Object { $_ -notmatch 'yaif-completion\.ps1' }) }
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
sed -i 's/$/\r/' $D/README.txt $D/LICENSE-*.txt $D/yaif-completion.ps1 $D/yaif-profile.ps1 $D/install.bat $D/uninstall.bat
(cd dist && zip -qr yaif-windows.zip yaif-windows) && ls -l dist/yaif-windows.zip
# Both installers show yaif.li's version in Settings > Apps. An MSI ProductVersion is numbers only,
# so the MSI gets 2.0.0 where NSIS shows the whole 2.0.0-beta.2.
V=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' yaif.li)
# Installer (sudo dnf install mingw32-nsis): dist/yaif-setup.exe
if command -v makensis >/dev/null; then makensis -V2 -DVERSION="$V" win/yaif.nsi && ls -l dist/yaif-setup.exe; else echo "makensis missing: no yaif-setup.exe"; fi
# MSI (sudo dnf install msitools): dist/yaif-setup.msi
if command -v wixl >/dev/null; then wixl -a x64 -D Version="${V%%-*}" -o dist/yaif-setup.msi win/yaif.wxs && ls -l dist/yaif-setup.msi; else echo "wixl missing: no yaif-setup.msi"; fi

# Release names, the shape release/pack.sh gives the Linux and macOS archives
# (yaif-<version>-<os>-<arch>); the release's SHA256SUMS is written when it is published.
n=yaif-$V-windows-x86_64
rm -f dist/$n*
for f in yaif-windows.zip:$n.zip yaif-setup.exe:$n-setup.exe yaif-setup.msi:$n.msi; do
  [ -f "dist/${f%%:*}" ] || continue
  mv "dist/${f%%:*}" "dist/${f#*:}"
done
ls -l dist/$n*
