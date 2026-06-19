#!/usr/bin/env python3
"""
Build a standalone NOVA Viewer executable for the current platform.

    python3 build.py

Output:
  macOS   → dist/NOVAViewer.app   (drag to /Applications, .nova auto-associates)
  Windows → dist/NOVAViewer.exe   (registers .nova on first launch)
  Linux   → dist/NOVAViewer + dist/install.sh
"""

import os, sys, shutil, subprocess, platform, plistlib

PLATFORM = platform.system()   # 'Darwin' | 'Windows' | 'Linux'
APP      = "NOVAViewer"
ENTRY    = "nova_viewer.py"
BUNDLE   = "com.nova.viewer"

# ── helpers ───────────────────────────────────────────────────────────────────

def run(cmd):
    print("$", " ".join(str(c) for c in cmd))
    subprocess.check_call(cmd)

def ensure_pyinstaller():
    try:
        import PyInstaller  # noqa: F401
    except ImportError:
        print("PyInstaller not found — installing...")
        run([sys.executable, "-m", "pip", "install", "pyinstaller", "--break-system-packages"])

# ── build ─────────────────────────────────────────────────────────────────────

def build():
    ensure_pyinstaller()
    _ensure_icons()

    args = [
        sys.executable, "-m", "PyInstaller",
        "--name", APP,
        "--clean",
        "--noconfirm",
        "--hidden-import", "PIL._tkinter_finder",
        "--hidden-import", "PIL.Image",
        "--hidden-import", "PIL.ImageTk",
        "--add-data", f"nova.py{os.pathsep}.",
        "--add-data", f"updater.py{os.pathsep}.",
    ]

    if PLATFORM == "Darwin":
        args += ["--windowed", f"--osx-bundle-identifier={BUNDLE}",
                 "--icon", "assets/nova_viewer.icns"]
    elif PLATFORM == "Windows":
        args += ["--windowed", "--onefile", "--icon", "assets/nova_viewer.ico"]
    else:
        args += ["--onefile"]

    args.append(ENTRY)
    run(args)

    if PLATFORM == "Darwin":
        _patch_plist_macos()
        print(f"\ndist/{APP}.app")
        print("   Drag to /Applications -- .nova files will open automatically.")

    elif PLATFORM == "Windows":
        print(f"\ndist/{APP}.exe")
        print("   .nova files register on first launch (no admin required).")

    else:
        _write_linux_extras()
        print(f"\ndist/{APP}")
        print("   Run  sudo dist/install.sh  to register .nova files system-wide.")

# ── macOS: patch Info.plist ───────────────────────────────────────────────────

def _ensure_icons():
    import importlib.util
    if importlib.util.find_spec("PIL") is None:
        return
    need_icns = PLATFORM == "Darwin" and not os.path.exists("assets/nova_viewer.icns")
    need_ico  = not os.path.exists("assets/nova_viewer.ico")
    if need_icns or need_ico:
        print("Generating icons…")
        import make_icon
        make_icon.make_png()
        make_icon.make_ico()
        if PLATFORM == "Darwin":
            make_icon.make_icns()


def _patch_plist_macos():
    path = f"dist/{APP}.app/Contents/Info.plist"
    with open(path, "rb") as f:
        pl = plistlib.load(f)

    try:
        import re as _re
        _m = _re.search(r'^VERSION = "(.+)"', open("updater.py").read(), _re.M)
        if _m:
            pl["CFBundleShortVersionString"] = _m.group(1)
            pl["CFBundleVersion"] = _m.group(1)
    except Exception:
        pass

    pl["CFBundleDocumentTypes"] = [{
        "CFBundleTypeName": "NOVA Image",
        "CFBundleTypeRole": "Viewer",
        "CFBundleTypeExtensions": ["nova"],
        "LSItemContentTypes": ["com.nova.image"],
    }]
    pl["UTExportedTypeDeclarations"] = [{
        "UTTypeIdentifier": "com.nova.image",
        "UTTypeDescription": "NOVA Image",
        "UTTypeConformsTo": ["public.image"],
        "UTTypeTagSpecification": {"public.filename-extension": ["nova"]},
    }]

    with open(path, "wb") as f:
        plistlib.dump(pl, f)
    print("  Patched Info.plist (.nova UTI declared).")

# ── Linux: .desktop + mime XML + install script ───────────────────────────────

def _write_linux_extras():
    dist = os.path.abspath("dist")
    exe  = os.path.join(dist, APP)

    # MIME type declaration
    mime_xml = f"""\
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="image/x-nova">
    <comment>NOVA Image</comment>
    <glob pattern="*.nova"/>
    <magic priority="50">
      <match type="string" offset="0" value="\\x89NOVA\\r\\n\\x1a\\n"/>
    </magic>
  </mime-type>
</mime-info>
"""
    with open(f"{dist}/nova-mime.xml", "w") as f:
        f.write(mime_xml)

    # .desktop entry
    desktop = f"""\
[Desktop Entry]
Name=NOVA Viewer
Comment=View and convert NOVA image files
Exec={exe} %f
Terminal=false
Type=Application
MimeType=image/x-nova;
Categories=Graphics;Viewer;
"""
    desktop_path = f"{dist}/{APP}.desktop"
    with open(desktop_path, "w") as f:
        f.write(desktop)

    # install script
    install_sh = f"""\
#!/bin/bash
set -e
DIST="$(cd "$(dirname "$0")" && pwd)"

install -m 755 "$DIST/{APP}" /usr/local/bin/
xdg-mime install --novendor "$DIST/nova-mime.xml"
cp "$DIST/{APP}.desktop" /usr/share/applications/
xdg-mime default {APP}.desktop image/x-nova
update-desktop-database /usr/share/applications/ 2>/dev/null || true

echo "NOVA Viewer installed. Double-clicking .nova files will open NOVA Viewer."
"""
    sh_path = f"{dist}/install.sh"
    with open(sh_path, "w") as f:
        f.write(install_sh)
    os.chmod(sh_path, 0o755)

# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    build()
