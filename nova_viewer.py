#!/usr/bin/env python3
"""NOVA Viewer — open, create and convert .nova files. Requires only stdlib + PIL."""
from __future__ import annotations

import os, struct, sys, threading, tkinter as tk
from tkinter import filedialog, messagebox, scrolledtext
from PIL import Image, ImageDraw, ImageTk
from PIL.ExifTags import TAGS as _EXIF_TAGS
import nova
try:
    import updater
    _HAS_UPDATER = True
except ImportError:
    _HAS_UPDATER = False


_RAW_EXTS = {'.dng','.cr2','.cr3','.nef','.arw','.orf','.rw2','.pef','.srw','.raf','.3fr','.erf','.mrw'}
_HEIC_EXTS = {'.heic','.heif','.hif'}


def _open_image(path: str) -> "Image.Image":
    """Open any image file, with optional rawpy/pillow-heif for RAW and HEIC formats."""
    ext = os.path.splitext(path)[1].lower()

    if ext in _HEIC_EXTS:
        try:
            import pillow_heif
            pillow_heif.register_heif_opener()
        except ImportError:
            raise RuntimeError(
                "HEIC/HEIF support requires pillow-heif.\n"
                "Install it with:  pip install pillow-heif")

    if ext in _RAW_EXTS:
        try:
            import rawpy, numpy as np
            with rawpy.imread(path) as raw:
                rgb = raw.postprocess(use_camera_wb=True, half_size=False, no_auto_bright=False)
            return Image.fromarray(rgb)
        except ImportError:
            raise RuntimeError(
                f"RAW format ({ext}) support requires rawpy and numpy.\n"
                "Install them with:  pip install rawpy numpy")

    return Image.open(path)


def _register_windows():
    """Register .nova file association and Start Menu shortcut in HKCU (no admin required)."""
    try:
        import winreg, subprocess  # type: ignore[import]
        exe = sys.executable if not getattr(sys, "frozen", False) else sys.argv[0]
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r"Software\Classes\.nova") as k:
            winreg.SetValue(k, "", winreg.REG_SZ, "NOVAImage")
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, r"Software\Classes\NOVAImage") as k:
            winreg.SetValue(k, "", winreg.REG_SZ, "NOVA Image File")
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER,
                               r"Software\Classes\NOVAImage\shell\open\command") as k:
            winreg.SetValue(k, "", winreg.REG_SZ, f'"{exe}" "%1"')
        # Start Menu shortcut
        start_menu = os.path.expandvars(
            r"%APPDATA%\Microsoft\Windows\Start Menu\Programs\NOVA Viewer.lnk")
        if not os.path.exists(start_menu):
            ps = (
                f'$ws = New-Object -ComObject WScript.Shell;'
                f'$s = $ws.CreateShortcut("{start_menu}");'
                f'$s.TargetPath = "{exe}";'
                f'$s.IconLocation = "{exe},0";'
                f'$s.Description = "NOVA Image Viewer";'
                f'$s.Save()'
            )
            subprocess.run(["powershell", "-WindowStyle", "Hidden", "-Command", ps],
                           capture_output=True)
    except Exception:
        pass


class NovaViewer(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("NOVA Viewer")
        self.geometry("900x650")
        self.configure(bg="#1a1a1a")

        self._frames = []
        self._frame_idx = 0
        self._frame_duration = 100
        self._playing = False
        self._play_job = None
        self._photo = None
        self._path = None

        self._build_menu()
        self._build_ui()
        if sys.platform != "darwin":   # macOS gets icon from .icns bundle; wm_iconphoto overrides Dock
            self._set_window_icon()

        # macOS: handle double-click on .nova file via Apple Event
        if sys.platform == "darwin":
            self.tk.createcommand("::tk::mac::OpenDocument",
                                  lambda *files: self.after(0, lambda: self._load(files[0])))

        # Windows: fix focus (prevents menu closing instantly), register associations
        if sys.platform == "win32":
            self.lift()
            self.focus_force()
            self.after(500, _register_windows)

        # Check for updates in background (3s delay to not slow startup)
        if _HAS_UPDATER:
            self.after(3000, self._check_update)

    # ── menu ──────────────────────────────────────────────────────────────────

    def _set_window_icon(self):
        try:
            size = 64
            mask = Image.new("L", (size, size), 0)
            ImageDraw.Draw(mask).rounded_rectangle([(0, 0), (size-1, size-1)],
                                                    radius=size//5, fill=255)
            bg = Image.new("RGBA", (size, size), (12, 18, 30, 255))
            result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            result.paste(bg, mask=mask)
            m, bar = int(size * 0.22), int(size * 0.12)
            t, b, l, r = m, size-m, m, size-m
            c = (228, 236, 255, 255)
            d = ImageDraw.Draw(result)
            d.rectangle([l, t, l+bar, b], fill=c)
            d.rectangle([r-bar, t, r, b], fill=c)
            d.polygon([(l+bar, t), (l+bar*2, t), (r, b), (r-bar, b)], fill=c)
            self._icon_photo = ImageTk.PhotoImage(result)
            self.wm_iconphoto(True, self._icon_photo)
        except Exception:
            pass

    def _build_menu(self):
        bar = tk.Menu(self)

        file_m = tk.Menu(bar, tearoff=0)
        file_m.add_command(label="Open .nova…",      accelerator="Cmd+O", command=self._open)
        file_m.add_command(label="Import image as .nova…",               command=self._import)
        file_m.add_separator()
        file_m.add_command(label="File Info…",       accelerator="Cmd+I", command=self._show_info)
        file_m.add_separator()
        file_m.add_command(label="Export as…",                           command=self._export)
        file_m.add_separator()
        file_m.add_command(label="Quit",             accelerator="Cmd+Q", command=self.quit)
        bar.add_cascade(label="File", menu=file_m)

        self.config(menu=bar)
        self.bind_all("<Command-o>", lambda _: self._open())
        self.bind_all("<Command-i>", lambda _: self._show_info())
        self.bind_all("<Command-q>", lambda _: self.quit())

    # ── layout ────────────────────────────────────────────────────────────────

    def _build_ui(self):
        self._canvas = tk.Canvas(self, bg="#1a1a1a", highlightthickness=0)
        self._canvas.pack(fill=tk.BOTH, expand=True)
        # _redraw bound later via _on_canvas_resize

        # Welcome screen — shown when no image is loaded
        self._welcome = tk.Frame(self._canvas, bg="#1a1a1a")
        tk.Label(self._welcome, text="NOVA", font=("Helvetica", 48, "bold"),
                 bg="#1a1a1a", fg="white").pack(pady=(0, 4))
        tk.Label(self._welcome, text="Open, create and convert .nova images",
                 font=("Helvetica", 13), bg="#1a1a1a", fg="#666").pack(pady=(0, 32))

        for label, cmd in [
            ("Open a .nova file",         self._open),
            ("Import & convert to .nova", self._import),
        ]:
            self._make_btn(self._welcome, label, cmd)

        self._canvas.bind("<Configure>", self._on_canvas_resize)
        self._welcome_win = self._canvas.create_window(0, 0, window=self._welcome, anchor="nw")
        self._show_welcome()

        bar = tk.Frame(self, bg="#242424", height=32)
        bar.pack(fill=tk.X, side=tk.BOTTOM)
        bar.pack_propagate(False)

        self._info = tk.Label(bar, text="Open a .nova file  ·  File > Open",
                              bg="#242424", fg="#777", font=("Helvetica", 11))
        self._info.pack(side=tk.LEFT, padx=12, pady=4)

        # Update banner — hidden until an update is found
        self._update_btn = tk.Label(bar, text="", bg="#1a6b2e", fg="white",
                                    font=("Helvetica", 11), padx=10, pady=0, cursor="hand2")
        self._update_btn.bind("<Button-1>", lambda _: self._install_update())
        self._update_btn.bind("<Enter>", lambda _: self._update_btn.config(bg="#1f8a3a"))
        self._update_btn.bind("<Leave>", lambda _: self._update_btn.config(bg="#1a6b2e"))
        self._update_info = {}

        # animation controls — hidden until an animated file is loaded
        self._anim_bar = tk.Frame(bar, bg="#242424")
        for text, cmd in [("◀", self._prev), ("▶", self._next)]:
            b = tk.Label(self._anim_bar, text=text, bg="#333", fg="white",
                         font=("Helvetica", 12), padx=8, pady=2, cursor="hand2")
            b.pack(side=tk.LEFT, padx=2)
            b.bind("<Button-1>", lambda _, c=cmd: c())
            b.bind("<Enter>",    lambda _, w=b: w.config(bg="#444"))
            b.bind("<Leave>",    lambda _, w=b: w.config(bg="#333"))
        self._play_btn = tk.Label(self._anim_bar, text="▶ Play", bg="#333", fg="white",
                                  font=("Helvetica", 12), padx=10, pady=2, cursor="hand2")
        self._play_btn.pack(side=tk.LEFT, padx=4)
        self._play_btn.bind("<Button-1>", lambda _: self._toggle_play())
        self._play_btn.bind("<Enter>",    lambda _: self._play_btn.config(bg="#444"))
        self._play_btn.bind("<Leave>",    lambda _: self._play_btn.config(bg="#333"))
        self._frame_lbl = tk.Label(self._anim_bar, text="", bg="#242424", fg="#777",
                                   font=("Helvetica", 11))
        self._frame_lbl.pack(side=tk.LEFT, padx=4)

    # ── file actions ──────────────────────────────────────────────────────────

    def _open(self):
        path = filedialog.askopenfilename(
            title="Open NOVA file",
            filetypes=[("NOVA images", "*.nova"), ("All files", "*.*")])
        if path:
            self._load(path)

    def _import(self):
        src = filedialog.askopenfilename(
            title="Import image",
            filetypes=[
                ("Images", "*.png *.jpg *.jpeg *.gif *.webp *.bmp *.tiff *.tif "
                           "*.heic *.heif *.dng *.cr2 *.cr3 *.nef *.arw *.orf "
                           "*.rw2 *.pef *.srw *.raf *.3fr"),
                ("All files", "*.*"),
            ])
        if not src:
            return

        dst = filedialog.asksaveasfilename(
            title="Save as .nova",
            defaultextension=".nova",
            initialfile=os.path.splitext(os.path.basename(src))[0],
            filetypes=[("NOVA images", "*.nova")])
        if not dst:
            return

        # Read source EXIF before showing the dialog
        try:
            src_img = _open_image(src)
            src_exif = src_img.getexif()
        except Exception:
            src_img = None
            src_exif = Image.Exif()

        opts = self._encode_dialog(src_exif)
        if opts is None:
            return

        try:
            final_exif = opts["exif"]
            exif_bytes = final_exif.tobytes() if final_exif and len(final_exif) else None
            # For RAW/HEIC, pre-open with _open_image so nova.encode gets a PIL Image
            # rather than a path (which would fall back to Image.open and likely fail).
            ext = os.path.splitext(src)[1].lower()
            source = _open_image(src) if ext in (_RAW_EXTS | _HEIC_EXTS) else src
            nova.encode(source, dst, quality=opts["quality"], mode=opts["mode"],
                        exif=exif_bytes)
            self._load(dst)
        except Exception as e:
            messagebox.showerror("Import failed", str(e))

    def _export(self):
        if not self._frames:
            messagebox.showinfo("No image", "Open a .nova file first.")
            return

        dst = filedialog.asksaveasfilename(
            title="Export image",
            defaultextension=".png",
            filetypes=[("PNG", "*.png"), ("JPEG", "*.jpg"),
                       ("TIFF", "*.tiff"), ("WebP", "*.webp"),
                       ("GIF", "*.gif")])
        if not dst:
            return

        try:
            # Re-attach stored EXIF to the exported file
            exif_bytes = None
            if self._path:
                meta = nova.decode_metadata(self._path)
                exif_bytes = meta.get('exif')

            save_kwargs = {}
            ext = os.path.splitext(dst)[1].lower()
            if exif_bytes and ext in ('.jpg', '.jpeg', '.tiff', '.tif', '.webp', '.png'):
                save_kwargs['exif'] = exif_bytes

            if len(self._frames) == 1:
                self._frames[0].save(dst, **save_kwargs)
            else:
                self._frames[0].save(dst, save_all=True,
                                     append_images=self._frames[1:], loop=0,
                                     **save_kwargs)
        except Exception as e:
            messagebox.showerror("Export failed", str(e))

    # ── encode options dialog ─────────────────────────────────────────────────

    def _encode_dialog(self, src_exif: "Image.Exif | None" = None):
        dlg = tk.Toplevel(self)
        dlg.title("Encode options")
        dlg.resizable(False, False)
        dlg.grab_set()
        dlg.configure(bg="#2a2a2a")

        result = {}
        # Working copy of EXIF that _exif_editor can mutate
        current_exif = [src_exif if src_exif is not None else Image.Exif()]

        def _dlg_btn(parent, text, cmd, color):
            lbl = tk.Label(parent, text=text, bg=color, fg="white",
                           font=("Helvetica", 12), padx=16, pady=6, cursor="hand2")
            lbl.pack(side=tk.RIGHT, padx=4)
            lbl.bind("<Button-1>", lambda _: cmd())
            lbl.bind("<Enter>",    lambda _: lbl.config(bg="#555" if color == "#444" else "#0066cc"))
            lbl.bind("<Leave>",    lambda _: lbl.config(bg=color))

        tk.Label(dlg, text="Mode", bg="#2a2a2a", fg="white").grid(
            row=0, column=0, padx=12, pady=(12, 4), sticky="w")
        mode_var = tk.StringVar(value="adaptive")
        for i, (m, desc) in enumerate([
            ("adaptive", "Auto — picks smallest"),
            ("lossless", "Pixel-perfect"),
            ("lossy",    "JPEG — smallest for photos"),
            ("express",  "JPEG + thumbnail — instant preview on slow storage"),
        ]):
            tk.Radiobutton(dlg, text=f"{m}  ({desc})", variable=mode_var, value=m,
                           bg="#2a2a2a", fg="white", selectcolor="#444",
                           activebackground="#2a2a2a", activeforeground="white").grid(
                row=i + 1, column=0, columnspan=2, padx=20, sticky="w")

        tk.Label(dlg, text="Quality", bg="#2a2a2a", fg="white").grid(
            row=5, column=0, padx=12, pady=(12, 0), sticky="w")
        quality_var = tk.IntVar(value=85)
        tk.Scale(dlg, from_=1, to=100, orient=tk.HORIZONTAL, variable=quality_var,
                 length=260, bg="#2a2a2a", fg="white", troughcolor="#444",
                 highlightthickness=0).grid(row=6, column=0, columnspan=2, padx=12, pady=(0, 12))

        # EXIF row
        exif_has = bool(src_exif and len(src_exif))
        exif_lbl = tk.Label(dlg,
            text=f"EXIF  ({'found from source' if exif_has else 'none'})",
            bg="#2a2a2a", fg="#aaa" if exif_has else "#555")
        exif_lbl.grid(row=7, column=0, padx=12, pady=(4, 0), sticky="w")

        def _open_exif_editor():
            edited = self._exif_editor(current_exif[0])
            if edited is not None:
                current_exif[0] = edited
                tag_count = len(edited)
                exif_lbl.config(
                    text=f"EXIF  ({tag_count} tag{'s' if tag_count != 1 else ''} set)",
                    fg="#6c8ef5")

        edit_lbl = tk.Label(dlg, text="Edit EXIF…", bg="#2a2a2a", fg="#6c8ef5",
                            font=("Helvetica", 11), cursor="hand2")
        edit_lbl.grid(row=7, column=1, padx=12, pady=(4, 0), sticky="e")
        edit_lbl.bind("<Button-1>", lambda _: _open_exif_editor())
        edit_lbl.bind("<Enter>",    lambda _: edit_lbl.config(fg="#93aff7"))
        edit_lbl.bind("<Leave>",    lambda _: edit_lbl.config(fg="#6c8ef5"))

        def ok():
            result["mode"]    = mode_var.get()
            result["quality"] = quality_var.get()
            result["exif"]    = current_exif[0]
            dlg.destroy()

        btn_row = tk.Frame(dlg, bg="#2a2a2a")
        btn_row.grid(row=8, column=0, columnspan=2, pady=(8, 12))
        _dlg_btn(btn_row, "Cancel", dlg.destroy, "#444")
        _dlg_btn(btn_row, "Encode", ok, "#0a84ff")

        dlg.wait_window()
        return result if result else None

    # ── EXIF editor dialog ────────────────────────────────────────────────────

    # Common editable tags: id → (label, type_hint)
    _EDITABLE_TAGS = [
        (270,   "Description"),
        (271,   "Make"),
        (272,   "Model"),
        (305,   "Software"),
        (306,   "DateTime"),        # "YYYY:MM:DD HH:MM:SS"
        (315,   "Artist"),
        (33432, "Copyright"),
    ]

    def _exif_editor(self, exif: "Image.Exif") -> "Image.Exif | None":
        dlg = tk.Toplevel(self)
        dlg.title("Edit EXIF")
        dlg.resizable(False, False)
        dlg.grab_set()
        dlg.configure(bg="#2a2a2a")

        result = [None]
        vars_ = {}

        tk.Label(dlg, text="Edit EXIF metadata", bg="#2a2a2a", fg="white",
                 font=("Helvetica", 13, "bold")).grid(
            row=0, column=0, columnspan=2, padx=16, pady=(14, 8), sticky="w")

        for row, (tag_id, label) in enumerate(self._EDITABLE_TAGS, start=1):
            tk.Label(dlg, text=label, bg="#2a2a2a", fg="#aaa",
                     font=("Helvetica", 11), width=14, anchor="e").grid(
                row=row, column=0, padx=(16, 6), pady=3, sticky="e")
            v = tk.StringVar(value=str(exif.get(tag_id, "")))
            vars_[tag_id] = v
            tk.Entry(dlg, textvariable=v, bg="#1e1e1e", fg="white", insertbackground="white",
                     relief="flat", font=("Helvetica", 11), width=34).grid(
                row=row, column=1, padx=(0, 16), pady=3)

        tk.Label(dlg, text="DateTime format: YYYY:MM:DD HH:MM:SS",
                 bg="#2a2a2a", fg="#555", font=("Helvetica", 9)).grid(
            row=len(self._EDITABLE_TAGS) + 1, column=1, padx=(0, 16), sticky="w")

        def ok():
            new_exif = Image.Exif()
            # Carry over any non-editable tags from the original
            for tid, val in exif.items():
                if tid not in dict(self._EDITABLE_TAGS):
                    new_exif[tid] = val
            # Apply edits
            for tag_id, _ in self._EDITABLE_TAGS:
                val = vars_[tag_id].get().strip()
                if val:
                    new_exif[tag_id] = val
                elif tag_id in new_exif:
                    del new_exif[tag_id]
            result[0] = new_exif
            dlg.destroy()

        def _btn(parent, text, cmd, color):
            lbl = tk.Label(parent, text=text, bg=color, fg="white",
                           font=("Helvetica", 12), padx=14, pady=6, cursor="hand2")
            lbl.pack(side=tk.RIGHT, padx=4)
            lbl.bind("<Button-1>", lambda _: cmd())
            lbl.bind("<Enter>",    lambda _: lbl.config(bg="#555" if color == "#444" else "#0066cc"))
            lbl.bind("<Leave>",    lambda _: lbl.config(bg=color))

        btn_row = tk.Frame(dlg, bg="#2a2a2a")
        btn_row.grid(row=len(self._EDITABLE_TAGS) + 2, column=0, columnspan=2, pady=(8, 14))
        _btn(btn_row, "Cancel", dlg.destroy, "#444")
        _btn(btn_row, "Apply", ok, "#0a84ff")

        dlg.wait_window()
        return result[0]

    # ── file info dialog ──────────────────────────────────────────────────────

    def _show_info(self):
        if not self._frames or not self._path:
            messagebox.showinfo("No file", "Open a .nova file first.")
            return

        dlg = tk.Toplevel(self)
        dlg.title("File Info")
        dlg.resizable(False, False)
        dlg.grab_set()
        dlg.configure(bg="#2a2a2a")

        def _row(parent, label, value, r):
            tk.Label(parent, text=label, bg="#2a2a2a", fg="#777",
                     font=("Helvetica", 11), width=18, anchor="e").grid(
                row=r, column=0, padx=(16, 8), pady=2, sticky="e")
            tk.Label(parent, text=str(value), bg="#2a2a2a", fg="white",
                     font=("Helvetica", 11), anchor="w").grid(
                row=r, column=1, padx=(0, 16), pady=2, sticky="w")

        tk.Label(dlg, text=os.path.basename(self._path),
                 bg="#2a2a2a", fg="white", font=("Helvetica", 13, "bold")).grid(
            row=0, column=0, columnspan=2, padx=16, pady=(14, 10), sticky="w")

        img = self._frames[0]
        sz = os.path.getsize(self._path)
        sz_str = f"{sz / 1024:.1f} KB" if sz < 1_000_000 else f"{sz / 1_048_576:.2f} MB"

        _row(dlg, "Dimensions", f"{img.width} × {img.height} px", 1)
        _row(dlg, "Color mode",  img.mode, 2)
        _row(dlg, "Frames",      len(self._frames), 3)
        _row(dlg, "File size",   sz_str, 4)

        # Parse stored EXIF
        meta = nova.decode_metadata(self._path)
        exif_bytes = meta.get('exif')

        sep = tk.Frame(dlg, bg="#3a3a3a", height=1)
        sep.grid(row=5, column=0, columnspan=2, sticky="ew", padx=16, pady=8)

        if exif_bytes:
            try:
                exif = Image.Exif()
                exif.load(exif_bytes)
                row_idx = 6
                displayed = 0
                for tag_id, value in exif.items():
                    name = _EXIF_TAGS.get(tag_id, f"Tag {tag_id}")
                    if isinstance(value, bytes):
                        continue   # skip binary blobs
                    _row(dlg, name, str(value)[:80], row_idx)
                    row_idx += 1
                    displayed += 1
                if not displayed:
                    tk.Label(dlg, text="EXIF present but no readable tags",
                             bg="#2a2a2a", fg="#555", font=("Helvetica", 11)).grid(
                        row=6, column=0, columnspan=2, padx=16, pady=4)
                    row_idx = 7
            except Exception as e:
                tk.Label(dlg, text=f"EXIF parse error: {e}",
                         bg="#2a2a2a", fg="#f87171", font=("Helvetica", 11)).grid(
                    row=6, column=0, columnspan=2, padx=16, pady=4)
                row_idx = 7
        else:
            tk.Label(dlg, text="No EXIF metadata stored",
                     bg="#2a2a2a", fg="#555", font=("Helvetica", 11)).grid(
                row=6, column=0, columnspan=2, padx=16, pady=4)
            row_idx = 7

        close = tk.Label(dlg, text="Close", bg="#444", fg="white",
                         font=("Helvetica", 12), padx=16, pady=6, cursor="hand2")
        close.grid(row=row_idx + 1, column=0, columnspan=2, pady=(8, 14))
        close.bind("<Button-1>", lambda _: dlg.destroy())
        close.bind("<Enter>",    lambda _: close.config(bg="#555"))
        close.bind("<Leave>",    lambda _: close.config(bg="#444"))

    # ── loading ───────────────────────────────────────────────────────────────

    def _load(self, path):
        self._stop()
        self._path = path
        self._frames = []
        self._frame_idx = 0
        self._frame_duration = 100
        self.title(f"NOVA Viewer — {os.path.basename(path)}")

        self._hide_welcome()

        # Express mode: show thumbnail instantly, decode full image in background
        preview = nova.decode_preview(path)
        if preview:
            self._frames = [preview]
            self._info.config(text="Express · loading full quality…", fg="#aaa")
            self._show(0)
            threading.Thread(target=self._load_full, args=(path,), daemon=True).start()
        else:
            self._load_full(path, show_immediately=True)

    def _load_full(self, path, show_immediately=False):
        try:
            frames = nova.decode(path)
        except Exception as e:
            self.after(0, lambda: messagebox.showerror("Failed to open", str(e)))
            return

        def _apply():
            self._frames = frames
            self._frame_idx = 0
            for ct, data in nova._read_all_chunks(path):
                if ct == nova.CHUNK_ANIM:
                    _, dur, _ = struct.unpack(">IHH", data)
                    self._frame_duration = max(dur, 20)
            self._update_status()
            self._show(0)
            if len(frames) > 1:
                self._anim_bar.pack(side=tk.RIGHT, padx=12, pady=2)
            else:
                self._anim_bar.pack_forget()

        self.after(0, _apply)

    def _make_btn(self, parent, text, cmd):
        """Label-based button — respects bg/fg on macOS unlike tk.Button."""
        lbl = tk.Label(parent, text=text, bg="#2c2c2e", fg="white",
                       font=("Helvetica", 13), padx=24, pady=12,
                       cursor="hand2", width=28)
        lbl.pack(pady=5)
        lbl.bind("<Button-1>",    lambda e: cmd())
        lbl.bind("<Enter>",       lambda e: lbl.config(bg="#3a3a3c"))
        lbl.bind("<Leave>",       lambda e: lbl.config(bg="#2c2c2e"))
        lbl.bind("<ButtonRelease-1>", lambda e: lbl.config(bg="#2c2c2e"))

    # ── welcome screen ────────────────────────────────────────────────────────

    def _show_welcome(self):
        self._canvas.itemconfigure(self._welcome_win, state="normal")

    def _hide_welcome(self):
        self._canvas.itemconfigure(self._welcome_win, state="hidden")

    def _on_canvas_resize(self, event=None):
        cw = self._canvas.winfo_width()
        ch = self._canvas.winfo_height()
        # Center the welcome frame
        self._welcome.update_idletasks()
        ww = self._welcome.winfo_reqwidth()
        wh = self._welcome.winfo_reqheight()
        x = max(0, (cw - ww) // 2)
        y = max(0, (ch - wh) // 2)
        self._canvas.coords(self._welcome_win, x, y)
        self._redraw()

    # ── display ───────────────────────────────────────────────────────────────

    def _show(self, idx):
        self._frame_idx = idx % len(self._frames)
        self._redraw()
        if len(self._frames) > 1:
            self._frame_lbl.config(text=f"{self._frame_idx + 1} / {len(self._frames)}")

    def _redraw(self, _event=None):
        if not self._frames:
            return
        self._canvas.delete("all")
        cw = self._canvas.winfo_width()
        ch = self._canvas.winfo_height()
        if cw < 2 or ch < 2:
            return

        img = self._frames[self._frame_idx]
        iw, ih = img.size
        scale = min(cw / iw, ch / ih, 1.0)
        nw, nh = max(1, int(iw * scale)), max(1, int(ih * scale))
        display = img.resize((nw, nh), Image.LANCZOS) if scale < 1.0 else img
        self._photo = ImageTk.PhotoImage(display)
        self._canvas.create_image(cw // 2, ch // 2, anchor=tk.CENTER, image=self._photo)

    def _update_status(self):
        if not self._frames or not self._path:
            return
        img = self._frames[0]
        sz = os.path.getsize(self._path)
        sz_str = f"{sz / 1024:.1f} KB" if sz < 1_000_000 else f"{sz / 1_048_576:.2f} MB"
        n = len(self._frames)
        anim = f" · {n} frames @ {self._frame_duration}ms" if n > 1 else ""
        self._info.config(text=f"{img.width}×{img.height} · {img.mode}{anim} · {sz_str}")

    # ── animation ─────────────────────────────────────────────────────────────

    def _prev(self):
        self._stop()
        self._show(self._frame_idx - 1)

    def _next(self):
        self._stop()
        self._show(self._frame_idx + 1)

    def _toggle_play(self):
        if self._playing:
            self._stop()
        else:
            self._playing = True
            self._play_btn.config(text="⏸ Pause")
            self._tick()

    def _tick(self):
        if not self._playing:
            return
        self._show(self._frame_idx + 1)
        self._play_job = self.after(self._frame_duration, self._tick)

    def _stop(self):
        self._playing = False
        self._play_btn.config(text="▶ Play")
        if self._play_job:
            self.after_cancel(self._play_job)
            self._play_job = None

    # ── auto-update ───────────────────────────────────────────────────────────

    def _check_update(self):
        def _on_update(info):
            self._update_info = info
            self.after(0, lambda: self._show_update_banner(info))
        updater.check_async(_on_update)  # type: ignore[possibly-unbound]

    def _show_update_banner(self, info):
        v = info.get("version", "?")
        notes = info.get("notes", "")
        label = f"▲ Update {v} available — {notes}" if notes else f"▲ Update {v} available"
        self._update_btn.config(text=label)
        self._update_btn.pack(side=tk.RIGHT, padx=8, pady=2)

    def _install_update(self):
        if not self._update_info:
            return
        self._update_btn.config(text="Downloading…")
        self._update_btn.unbind("<Button-1>")

        def _progress(msg):
            self.after(0, lambda: self._update_btn.config(text=msg))

        def _done():
            self.after(0, lambda: self._update_btn.config(text="Restarting…"))

        def _error(msg):
            self.after(0, lambda: (
                messagebox.showerror("Update failed", msg),
                self._update_btn.config(text="Update failed")
            ))

        updater.install_async(self._update_info, _progress, _done, _error)  # type: ignore[possibly-unbound]


if __name__ == "__main__":
    app = NovaViewer()
    if len(sys.argv) > 1:
        app.after(100, lambda: app._load(sys.argv[1]))
    app.mainloop()
