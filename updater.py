"""
Auto-updater for NOVA Viewer.

Set UPDATE_URL to a JSON endpoint that returns:
  { "version": "1.2.0",
    "notes": "What changed",
    "download": { "darwin": "https://…/NOVAViewer-mac.zip",
                  "win32":  "https://…/NOVAViewer.exe",
                  "linux":  "https://…/NOVAViewer" } }
"""
from __future__ import annotations

import io, json, os, shutil, subprocess, sys, tempfile, threading, urllib.request

VERSION = "1.0.0"
UPDATE_URL = "https://github.com/Thibault-Savenkoff/nova/releases/latest/download/version.json"


# ── public API ────────────────────────────────────────────────────────────────

def check_async(on_update, on_error=None):
    """Fetch version info in background. Calls on_update(info) if newer, else nothing."""
    def _run():
        try:
            with urllib.request.urlopen(UPDATE_URL, timeout=5) as r:
                info = json.load(r)
            if _newer(info["version"], VERSION):
                on_update(info)
        except Exception as e:
            if on_error:
                on_error(e)
    threading.Thread(target=_run, daemon=True).start()


def install_async(info, on_progress, on_done, on_error):
    """Download and apply update in background."""
    url = info.get("download", {}).get(sys.platform)
    if not url:
        on_error(f"No download available for {sys.platform}")
        return

    def _run():
        try:
            tmp = tempfile.mkdtemp(prefix="nova_update_")
            filename = url.rsplit("/", 1)[-1]
            dest = os.path.join(tmp, filename)

            # Download with progress
            with urllib.request.urlopen(url, timeout=60) as r:
                total = int(r.headers.get("Content-Length", 0))
                done  = 0
                with open(dest, "wb") as f:
                    while True:
                        chunk = r.read(65536)
                        if not chunk:
                            break
                        f.write(chunk)
                        done += len(chunk)
                        if total:
                            on_progress(f"Downloading… {done * 100 // total}%")

            on_progress("Installing…")
            _apply(dest, tmp)
            on_done()                    # only reached if _apply doesn't sys.exit
        except Exception as e:
            on_error(str(e))

    threading.Thread(target=_run, daemon=True).start()


# ── internals ─────────────────────────────────────────────────────────────────

def _newer(remote: str, local: str) -> bool:
    def v(s): return tuple(int(x) for x in s.split("."))
    return v(remote) > v(local)


def _own_path() -> str | None:
    """Path to the running .app / .exe / binary (None if running from source)."""
    if not getattr(sys, "frozen", False):
        return None
    exe = os.path.abspath(sys.executable)
    if sys.platform == "darwin":
        # .../NOVAViewer.app/Contents/MacOS/NOVAViewer → .../NOVAViewer.app
        return os.path.normpath(os.path.join(exe, "..", "..", ".."))
    return exe


def _apply(downloaded: str, tmp: str):
    app = _own_path()
    if not app:
        raise RuntimeError("Cannot update: running from source, not a built binary.")

    if sys.platform == "darwin":
        new_app = os.path.join(tmp, "NOVAViewer.app")
        if downloaded.endswith(".zip"):
            subprocess.check_call(["unzip", "-q", downloaded, "-d", tmp])
        else:
            new_app = downloaded
        # Replace bundle in-place (safe while running; new version loads on next open)
        subprocess.check_call(["rsync", "-a", "--delete",
                                new_app + "/", app + "/"])
        subprocess.Popen(["open", app])
        sys.exit(0)

    elif sys.platform == "win32":
        # Run NSIS silent install to the same directory as the current exe.
        # /D= must be last and unquoted; use RunAs if under Program Files.
        instdir = os.path.dirname(app)
        pf = os.environ.get("PROGRAMFILES", "C:\\Program Files")
        needs_admin = instdir.lower().startswith(pf.lower())
        verb = "-Verb RunAs " if needs_admin else ""
        ps = (
            f'Start-Sleep -Seconds 2; '
            f'Start-Process "{downloaded}" -ArgumentList "/S","/D={instdir}" {verb}-Wait; '
            f'Start-Process "{app}"'
        )
        subprocess.Popen(
            ["powershell", "-WindowStyle", "Hidden", "-NonInteractive", "-Command", ps],
            creationflags=subprocess.DETACHED_PROCESS,
        )
        sys.exit(0)

    else:  # Linux
        os.chmod(downloaded, 0o755)
        shutil.copy2(downloaded, app)
        subprocess.Popen([app] + sys.argv[1:])
        sys.exit(0)
