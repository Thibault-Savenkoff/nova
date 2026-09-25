#!/usr/bin/env bash
# YAIF installer: downloads (or unpacks --from) a release, installs the
# yaif command, its zsh completion and the .yaif MIME type, then offers to
# build the viewer plugins (Qt/KDE, GNOME/glycin, GTK/gdk-pixbuf) for
# whichever of those are present on this system.
#
# Also the uninstaller (--uninstall): every file and rc-file line this
# script writes is recorded in a manifest, and uninstalling only ever
# removes paths read back from that manifest -- never a directory, never
# a guessed or computed path.
#
#   curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/yaif/v2/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Thibault-Savenkoff/yaif/v2/install.sh | bash -s -- --uninstall
#
# Bash 3.2 compatible (macOS ships nothing newer): no arrays, no [[ ]].
set -eu

repo=Thibault-Savenkoff/yaif
prefix=$HOME/.local
system=0
plugins=1
heic_hdr=1
deps=1
yes=0
from=
uninstall=0
version=
verbose=0
kde_thumb=0
CC=${CC:-cc}
# Set by test/install.sh to redirect system-wide (root) installs into a
# fake root instead of touching the real system directories or needing
# real sudo. Empty in a normal install.
TEST_ROOT=${YAIF_TEST_ROOT:-}
# Test-only: overrides the GitHub URLs with a local server. Empty in a
# normal install.
RELEASE_BASE=${YAIF_RELEASE_BASE:-https://github.com/$repo/releases/download}
# The releases' Atom feed, not the REST API: the API allows 60 requests an hour per IP address
# without a token, and a few installs plus other tools on the same network used them up (403).
FEED=${YAIF_FEED:-https://github.com/$repo/releases.atom}

usage() {
  cat <<'EOF'
YAIF installer

Usage:
  install.sh [options]
  install.sh --uninstall [--prefix DIR | --system]

Options:
  --system        install into /usr/local (needs sudo) instead of ~/.local
  --prefix DIR    install into DIR instead of ~/.local or /usr/local
  --version X.Y.Z install this version instead of the latest v2 release
  --from FILE     install from a local .tar.gz instead of downloading
                  (run from an unpacked archive, it installs that archive's files)
  --no-plugins    skip the Qt/KDE/GNOME/GTK viewer plugins
  --no-deps       skip checking for the HEIC/AVIF/WebP/RAW libraries
  --no-heic-hdr   don't build libyaif-heif (then .heic output has no HDR gain map)
  -y, --yes       don't ask before touching ~/.zshrc or building plugins
  --verbose       print every command this script runs (always shown on failure)
  --uninstall     remove everything a previous run installed
  -h, --help      this message
EOF
}

while [ $# -gt 0 ]; do
  case $1 in
    --system) system=1 ;;
    --prefix) [ $# -ge 2 ] || { echo "install.sh: --prefix needs a value" >&2; exit 1; }; prefix=$2; shift ;;
    --version) [ $# -ge 2 ] || { echo "install.sh: --version needs a value" >&2; exit 1; }; version=$2; shift ;;
    --from) [ $# -ge 2 ] || { echo "install.sh: --from needs a value" >&2; exit 1; }; from=$2; shift ;;
    --no-plugins) plugins=0 ;;
    --no-deps) deps=0 ;;
    --no-heic-hdr) heic_hdr=0 ;;
    -y|--yes) yes=1 ;;
    --verbose) verbose=1 ;;
    --uninstall) uninstall=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done
[ $system = 1 ] && prefix=/usr/local
[ $system = 1 ] && owner=root || owner=user

# ---- output helpers ----
step() { printf '\n==> %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
ok()   { printf '    \xe2\x9c\x93 %s\n' "$1"; }
warn() { printf '    ! %s\n' "$1" >&2; }
die()  { printf 'Error: %s\n' "$1" >&2; exit 1; }

pretty() {  # pretty <path>: $HOME shown as ~, for messages only (never for what we write to disk)
  case $1 in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    "$HOME") printf '~' ;;
    *) printf '%s' "$1" ;;
  esac
}

ask() {  # ask "question" -> 0=yes. Piped (curl | bash), stdin is the script: the question goes to
         # the terminal (/dev/tty) instead; with no terminal at all (CI, Docker) the answer is no.
  [ $yes = 1 ] && { info "$1 y (--yes)"; return 0; }
  if [ -t 0 ]; then
    printf '    %s [y/N] ' "$1" >&2
    read -r reply || reply=n
  elif { : </dev/tty; } 2>/dev/null; then
    printf '    %s [y/N] ' "$1" >&2
    read -r reply </dev/tty || reply=n
  else
    reply=n
    info "$1 n (no terminal to ask; pass --yes)"
  fi
  case $reply in [Yy]*) return 0 ;; *) return 1 ;; esac
}

run() {  # run user|root <cmd...>: runs quietly unless --verbose, but always shows the command (with
         # paths shortened by pretty) it if it fails; sudo's root ones unless redirected to TEST_ROOT
  local kind=$1 a shown="" status; shift
  [ "$kind" = root ] && [ -z "$TEST_ROOT" ] && [ "$(id -u)" != 0 ] && set -- sudo "$@"
  [ $verbose = 1 ] && { for a in "$@"; do shown="$shown $(pretty "$a")"; done; printf '    $ %s\n' "${shown# }"; }
  if "$@"; then status=0; else status=$?; fi
  if [ $status -ne 0 ] && [ $verbose = 0 ]; then
    for a in "$@"; do shown="$shown $(pretty "$a")"; done
    printf '    $ %s\n' "${shown# }" >&2
  fi
  return $status
}

# insert_before <file> <line-number-or-empty> <text>: inserts, or appends if <line-number> is empty.
# Portable (no sed -i, whose -i flag differs between GNU and BSD/macOS sed).
insert_before() {
  local file=$1 at=$2 text=$3 t
  t=$(mktemp)
  if [ -n "$at" ]; then
    awk -v n="$at" -v t="$text" 'NR==n{print t} {print}' "$file" > "$t"
  else
    cat "$file" > "$t"
    printf '%s\n' "$text" >> "$t"
  fi
  cat "$t" > "$file"
  rm -f "$t"
}

# ---- manifest: what we installed, read back (in reverse) by --uninstall ----
# One of "user|root <path>" or "line <rc-file><TAB><text>" or "dolphin <previous Plugins= value>" per line.
manifest="$prefix/share/yaif/installed.txt"
record() {
  local line="$*"
  mkdir -p "$(dirname "$manifest")" 2>/dev/null || true
  if [ -w "$(dirname "$manifest")" ]; then
    grep -qxF -- "$line" "$manifest" 2>/dev/null || printf '%s\n' "$line" >> "$manifest"
  else
    sudo mkdir -p "$(dirname "$manifest")"
    sudo grep -qxF -- "$line" "$manifest" 2>/dev/null || printf '%s\n' "$line" | sudo tee -a "$manifest" > /dev/null
  fi
}

install_file() {  # install_file user|root <source> <destination> <mode>
  local dest=$3
  [ "$1" = root ] && dest=$TEST_ROOT$3
  run "$1" mkdir -p "$(dirname "$dest")"
  run "$1" install -m "$4" "$2" "$dest"
  record "$1" "$dest"
}

add_rc_line() {  # add_rc_line <line> <question> <ok-suffix>: append <line> to ~/.zshrc if it isn't there
  local line=$1 prompt=$2 suffix=$3 rc="$HOME/.zshrc"
  [ -f "$rc" ] || { warn "no ~/.zshrc, add manually: $line"; return 0; }
  if grep -qxF -- "$line" "$rc" 2>/dev/null; then
    record line "$rc"$'\t'"$line"
    ok "~/.zshrc already adds it $suffix"
    return 0
  fi
  ask "$prompt" || return 0
  printf '%s\n' "$line" >> "$rc"
  record line "$rc"$'\t'"$line"
  ok "added to ~/.zshrc $suffix"
}

add_fpath_line() {  # like add_rc_line, but inserted before compinit/oh-my-zsh (they read fpath once)
  local dir=$1 rc="$HOME/.zshrc" line at
  line="fpath=($dir \$fpath)   # YAIF completion"
  [ -f "$rc" ] || { warn "no ~/.zshrc, add manually before compinit: $line"; return 0; }
  if grep -qxF -- "$line" "$rc" 2>/dev/null; then
    record line "$rc"$'\t'"$line"
    ok "~/.zshrc already adds $(pretty "$dir")"
    return 0
  fi
  ask "zsh does not look in $(pretty "$dir"). Add it to ~/.zshrc (before compinit)?" || return 0
  # A failed match (no compinit yet) is not an error: append at the end instead.
  at=$(grep -nE '^[^#]*(source .*oh-my-zsh\.sh|compinit)' "$rc" | head -1 | cut -d: -f1) || at=
  if [ -n "$at" ]; then
    insert_before "$rc" "$at" "$line"
  else
    insert_before "$rc" "" "$line"
    info "added at the end; move it above compinit if you add one later"
  fi
  record line "$rc"$'\t'"$line"
  ok "added to ~/.zshrc; open a new terminal (if Tab still lists files: rm ~/.zcompdump*)"
}

# ---- uninstall ----
enable_dolphin_thumbnailer() {
  if ! command -v kreadconfig6 >/dev/null 2>&1 || ! command -v kwriteconfig6 >/dev/null 2>&1; then
    info "kreadconfig6/kwriteconfig6 not found, tick YAIF Images in Dolphin's preview settings"
    return 0
  fi
  local cur new
  cur=$(kreadconfig6 --file dolphinrc --group PreviewSettings --key Plugins 2>/dev/null) || cur=
  # The plugin's id is its file name, libyaifthumb (cmake adds "lib"). No Plugins= list at all means
  # Dolphin's defaults, which include every new thumbnailer: writing one would switch the others off.
  case ",$cur," in
    ,,) ok "Dolphin uses its default thumbnailers, the YAIF one included (restart Dolphin)" ;;
    *,libyaifthumb,*) ok "Dolphin already uses the YAIF thumbnailer" ;;
    *)
      new=$cur,libyaifthumb
      run user kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins "$new" ||
        { warn "could not enable the Dolphin thumbnailer"; return 0; }
      record dolphin "$cur"
      ok "Dolphin thumbnails enabled for .yaif (restart Dolphin)"
      ;;
  esac
}

remove_dolphin_thumbnailer() {  # $rest: the pre-install Plugins= value, read by do_uninstall's caller
  command -v kwriteconfig6 >/dev/null 2>&1 || return 0
  if [ -n "$rest" ]; then
    run user kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins "$rest" || return 0
  else
    run user kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins --delete || return 0
  fi
  ok "Dolphin no longer uses the YAIF thumbnailer"
}

refresh_caches() {
  command -v update-mime-database >/dev/null 2>&1 && run "$owner" update-mime-database "$prefix/share/mime" 2>/dev/null || true
}

do_uninstall() {
  step "Uninstalling YAIF ($(pretty "$prefix"))"
  [ -f "$manifest" ] || die "nothing to uninstall: $manifest not found (installed with another --prefix?)"
  local kind rest file text
  # Undo in reverse so, e.g., an rc-file line inserted before another added line still matches.
  tac "$manifest" 2>/dev/null > "$tmp/manifest" || tail -r "$manifest" > "$tmp/manifest"
  while IFS=' ' read -r kind rest; do
    case $kind in
      user|root)
        # A single recorded file, never a directory: nothing here can turn into "rm -rf" of anything else.
        [ -n "$rest" ] || continue
        [ -e "$rest" ] || { info "already gone: $(pretty "$rest")"; continue; }
        run "$kind" rm -f -- "$rest" && ok "removed $(pretty "$rest")" ;;
      line)
        file=${rest%%$'\t'*} text=${rest#*$'\t'}
        if [ -n "$file" ] && [ -f "$file" ] && grep -qxF -- "$text" "$file"; then
          # grep -v can exit 1 if removing $text empties the file -- not an error, so don't gate on it.
          grep -vxF -- "$text" "$file" > "$tmp/rc" || true
          cat "$tmp/rc" > "$file"
          ok "removed from $(pretty "$file"): $text"
        fi ;;
      dolphin)
        remove_dolphin_thumbnailer ;;
    esac
  done < "$tmp/manifest"
  refresh_caches
  rm -f -- "$manifest"
  ok "YAIF is uninstalled."
}

# ---- download / verify / unpack ----
find_release() {
  step "Finding the YAIF release"
  local tag
  if [ -n "$version" ]; then
    tag="v$version"
  else
    # v1 ("YAIF Viewer") releases are also published, and one of them is the repo's "latest":
    # filter to v2.* tags instead of trusting "latest".
    tag=$(curl -fsSL "$FEED" | grep -o 'releases/tag/v2\.[^"<]*' | head -1 | sed 's#.*/##') || tag=
    [ -n "$tag" ] || die "no v2 release found on github.com/$repo"
    info "Latest v2 release on github.com/$repo"
  fi
  version=${tag#v}
  # macOS: one universal binary (Apple Silicon + Intel) since 2.0.0-beta.6, one archive per
  # architecture before.
  archive="yaif-$version-$os-$arch.tar.gz"
  if [ "$os" = macos ] && curl -fsL -r 0-0 -o /dev/null "$RELEASE_BASE/$tag/yaif-$version-macos-universal.tar.gz"; then
    archive="yaif-$version-macos-universal.tar.gz"
  fi
  url="$RELEASE_BASE/$tag/$archive"
  ok "version $version, for $os $arch"
}

download() {
  step "Downloading $archive"
  curl -fSL# -o "$tmp/$archive" "$url" || die "download failed: $url"
}

verify() {
  local want got
  # One SHA256SUMS per release since 2.0.0-beta.6, a .sha256 per file before.
  want=$(curl -fsL "$RELEASE_BASE/v$version/SHA256SUMS" | awk -v f="$archive" '$2 == f || $2 == "*" f {print $1}') || want=
  [ -n "$want" ] || want=$(curl -fsSL "$url.sha256" | awk '{print $1}') || want=
  [ -n "$want" ] || die "could not fetch the checksum for $archive"
  got=$(sha256sum "$tmp/$archive" | awk '{print $1}')
  [ "$want" = "$got" ] || die "SHA-256 mismatch for $archive: the download is corrupt or was altered. Nothing was installed."
  ok "SHA-256 checked ($got)"
}

unpack() {
  step "Unpacking $archive"
  tar -xzf "$tmp/$archive" -C "$tmp" || die "could not unpack $archive"
  src="$tmp/${archive%.tar.gz}"
  [ -d "$src" ] || die "unexpected archive layout: ${archive%.tar.gz}/ not found"
  [ $verbose = 1 ] && info "$(pretty "$src")"
  return 0
}

# ---- install steps ----
install_bin() {
  step "Installing the yaif command"
  install_file "$owner" "$src/bin/yaif" "$prefix/bin/yaif" 755
  # A copy of this script, so uninstalling needs neither the network nor the archive.
  install_file "$owner" "$src/install.sh" "$prefix/share/yaif/install.sh" 755
  ok "yaif $version -> $(pretty "$prefix/bin/yaif")"
  case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *)
      warn "$(pretty "$prefix/bin") is not in PATH"
      add_rc_line "export PATH=\"$prefix/bin:\$PATH\"   # YAIF" \
        "Add it to ~/.zshrc?" "(open a new terminal)" ;;
  esac
}

install_completion() {
  step "Installing shell completion"
  local dir="$prefix/share/zsh/site-functions"
  install_file "$owner" "$src/completions/_yaif" "$dir/_yaif" 644
  add_fpath_line "$dir"
  # bash and fish auto-load from these locations (if the shell/package is present): no rc-file edit.
  install_file "$owner" "$src/completions/yaif.bash" "$prefix/share/bash-completion/completions/yaif" 644
  install_file "$owner" "$src/completions/yaif.fish" "$prefix/share/fish/vendor_completions.d/yaif.fish" 644
  ok "bash and fish pick it up automatically (a new shell; bash needs the bash-completion package)"
}

install_mime() {
  step "Registering the .yaif file type (image/x-yaif)"
  install_file "$owner" "$src/plugins/mime/yaif.xml" "$prefix/share/mime/packages/yaif.xml" 644
  if command -v update-mime-database >/dev/null 2>&1; then
    run "$owner" update-mime-database "$prefix/share/mime" || warn "update-mime-database failed"
    ok "file managers now know .yaif files"
  else
    warn "update-mime-database not found; .yaif files won't get an icon/thumbnail until it runs"
  fi
}

check_lib() {  # check_lib <linux-soname> <macos-dylib> <label>
  local found=0 d
  case $os in
    linux)
      command -v ldconfig >/dev/null 2>&1 && ldconfig -p 2>/dev/null | grep -q "$1" && found=1 ;;
    macos)
      for d in /opt/homebrew/lib /usr/local/lib; do [ -e "$d/$2" ] && { found=1; break; }; done ;;
  esac
  if [ $found = 1 ]; then ok "$3"; else warn "$3 (not found)"; fi
}

check_libs() {
  [ $deps = 1 ] || return 0
  step "Checking the libraries yaif uses for other formats"
  info "yaif runs without them; each one adds formats (HEIC, AVIF, WebP, RAW)."
  check_lib libheif.so.1 libheif.1.dylib "libheif: HEIC, HEIF, AVIF"
  check_lib libavif.so.16 libavif.16.dylib "libavif: AVIF with an HDR gain map"
  check_lib libwebp.so.7 libwebp.7.dylib "libwebp: WebP output"
  check_lib libraw_r.so.25 libraw_r.25.dylib "LibRaw: camera RAW"
}

# libyaif-heif: libheif with its gain-map pull request (libheif-gainmap/build.sh), which yaif loads
# only to write a .heic that keeps the photo's HDR. Built here, like the plugins: no released libheif
# can do it. Skipped (with the command to get the tools) when cmake or a compiler is missing, and
# not rebuilt when the recipe has not changed since the last install.
install_heic_hdr() {
  local lib=libyaif-heif.so miss="" t stamp dir
  [ $os = macos ] && lib=libyaif-heif.dylib
  if [ $heic_hdr = 0 ]; then
    step "HEIC with HDR skipped (--no-heic-hdr)"
    return 0
  fi
  step "HEIC with HDR (libyaif-heif)"
  stamp=$(cat "$src/libheif-gainmap/build.sh" "$src/libheif-gainmap/pr1503.patch" | cksum | awk '{print $1}')
  dir=$prefix/lib/yaif
  [ $owner = root ] && dir=$TEST_ROOT$dir
  if [ -f "$dir/$lib" ] && [ "$(cat "$dir/libyaif-heif.stamp" 2>/dev/null)" = "$stamp" ]; then
    ok "already built, unchanged"
    return 0
  fi
  for t in cmake cc c++ patch; do command -v $t >/dev/null 2>&1 || miss="$miss $t"; done
  if [ -n "$miss" ]; then
    warn "not built, missing:$miss -- .heic output will be SDR only (.avif and .jpg keep the HDR)"
    if [ $os = macos ]; then info "Get them:  xcode-select --install && brew install cmake"
    elif command -v apt-get >/dev/null 2>&1; then info "Get them:  sudo apt install cmake g++ patch"
    elif command -v dnf >/dev/null 2>&1; then info "Get them:  sudo dnf install cmake gcc-c++ patch"
    elif command -v pacman >/dev/null 2>&1; then info "Get them:  sudo pacman -S cmake gcc patch"
    fi
    info "then run this installer again."
    return 0
  fi
  info "No released libheif can write HDR into a HEIC: building one that can (1-3 min)..."
  if ! run user sh "$src/libheif-gainmap/build.sh" "$tmp/heif" "$tmp/$lib" > "$tmp/heif.log" 2>&1; then
    tail -20 "$tmp/heif.log" >&2
    warn "libyaif-heif: build failed (log above) -- .heic output will be SDR only"
    return 0
  fi
  command -v strip >/dev/null 2>&1 && strip -x "$tmp/$lib" 2>/dev/null || true
  printf '%s\n' "$stamp" > "$tmp/libyaif-heif.stamp"
  install_file "$owner" "$tmp/$lib" "$prefix/lib/yaif/$lib" 644
  install_file "$owner" "$tmp/libyaif-heif.stamp" "$prefix/lib/yaif/libyaif-heif.stamp" 644
  ok "yaif decode photo.yaif photo.heic now keeps the HDR gain map"
}

# cmake_plugin <dir> <label>: builds plugins/<dir>, installs it (Qt's own system plugin dir), records the files.
cmake_plugin() {
  local b="$tmp/build-$1" f
  run user cmake -S "$src/plugins/$1" -B "$b" -DCMAKE_BUILD_TYPE=Release > "$tmp/$1.log" 2>&1 ||
    { tail -20 "$tmp/$1.log" >&2; warn "$2: configuration failed (log above)"; return 1; }
  # A bare --parallel is an unbounded make -j (all files at once, out of memory): one job per core.
  run user cmake --build "$b" --parallel "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" > "$tmp/$1.log" 2>&1 ||
    { tail -20 "$tmp/$1.log" >&2; warn "$2: build failed (log above)"; return 1; }
  DESTDIR=$TEST_ROOT run root cmake --install "$b" > "$tmp/$1.log" 2>&1 ||
    { tail -20 "$tmp/$1.log" >&2; warn "$2: install failed (log above)"; return 1; }
  # install_manifest.txt has no trailing newline after the last path: "|| [ -n "$f" ]" still reads it.
  while read -r f || [ -n "$f" ]; do record root "$f"; done < "$b/install_manifest.txt"
  ok "$2 installed"
}

has_kf6kio() {  # KDE Frameworks ship CMake package files, no pkg-config .pc: look for KF6KIOConfig.cmake
  local d
  for d in /usr/lib*/cmake /usr/lib/*/cmake /usr/local/lib*/cmake /usr/share/cmake; do
    [ -f "$d/KF6KIO/KF6KIOConfig.cmake" ] && return 0
  done
  return 1
}

drop_pixbuf_thumbnailer() {  # an earlier install's yaif.thumbnailer, a second "YAIF" in Dolphin (see below)
  local thumb="$TEST_ROOT/usr/share/thumbnailers/yaif.thumbnailer"
  if cmp -s "$src/plugins/gdk-pixbuf/yaif.thumbnailer" "$thumb"; then
    run root rm -f -- "$thumb" && ok "removed $(pretty "$thumb") (Dolphin listed YAIF twice)"
  fi
  return 0
}

make_gdk_pixbuf_plugin() {
  local so="$tmp/libpixbufloader-yaif.so" moduledir
  moduledir=$(pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0 2>/dev/null) || moduledir=
  [ -n "$moduledir" ] || { warn "gdk-pixbuf loader: gdk_pixbuf_moduledir unknown, skipped"; return 1; }
  # shellcheck disable=SC2046  # pkg-config's output must split into separate flags.
  run user "$CC" -O2 -std=c99 -Wall -fPIC -shared \
    -I"$src/libyaif" "$src/plugins/gdk-pixbuf/io-yaif.c" "$src/libyaif/yaifdec.c" -o "$so" \
    $(pkg-config --cflags --libs gdk-pixbuf-2.0) -lpthread \
    > "$tmp/gdk-pixbuf.log" 2>&1 ||
    { tail -20 "$tmp/gdk-pixbuf.log" >&2; warn "gdk-pixbuf loader: build failed (log above)"; return 1; }
  install_file root "$so" "$moduledir/libpixbufloader-yaif.so" 644
  # Dolphin lists freedesktop .thumbnailer files next to its own plugins: with the KDE thumbnailer
  # installed, this one would show as a second "YAIF" entry. It is for Nautilus/older GNOME only.
  [ $kde_thumb = 1 ] || install_file root "$src/plugins/gdk-pixbuf/yaif.thumbnailer" "/usr/share/thumbnailers/yaif.thumbnailer" 644
  if command -v gdk-pixbuf-query-loaders-64 >/dev/null 2>&1; then
    run root gdk-pixbuf-query-loaders-64 --update-cache
  elif command -v gdk-pixbuf-query-loaders >/dev/null 2>&1; then
    run root gdk-pixbuf-query-loaders --update-cache
  fi
  ok "gdk-pixbuf loader installed"
}

cargo_glycin_plugin() {
  # glycin-2.pc has no 'loaderdir' variable (recent glycin: loaders live under a versioned
  # "<API version>+" directory, e.g. /usr/libexec/glycin-loaders/2+, discovered by convention, not
  # by pkg-config). Built from the .pc's own 'prefix', matching every glycin-loaders package layout
  # observed so far (glycin-heif, glycin-svg, ...).
  local prefix execdir confdir bin_out name
  prefix=$(pkg-config --variable=prefix glycin-2 2>/dev/null) || prefix=
  [ -n "$prefix" ] || prefix=/usr
  execdir="$prefix/libexec/glycin-loaders/2+"
  confdir="$prefix/share/glycin-loaders/2+/conf.d"
  run user cargo build --release --manifest-path "$src/plugins/glycin/Cargo.toml" --target-dir "$tmp/glycin" \
    > "$tmp/glycin.log" 2>&1 ||
    { tail -20 "$tmp/glycin.log" >&2; warn "glycin loader: build failed (log above)"; return 1; }
  bin_out=$(find "$tmp/glycin/release" -maxdepth 1 -type f -name 'glycin-yaif*' ! -name '*.d' | head -1)
  [ -n "$bin_out" ] || { warn "glycin loader: build produced no binary, skipped"; return 1; }
  name=$(basename "$bin_out")
  install_file root "$bin_out" "$execdir/$name" 755
  printf '[loader:image/x-yaif]\nExec=%s/%s\n' "$execdir" "$name" > "$tmp/glycin-yaif.conf"
  install_file root "$tmp/glycin-yaif.conf" "$confdir/glycin-yaif.conf" 644
  # Nautilus thumbnails: glycin-thumbnailer is a generic tool that thumbnails whatever glycin can
  # load, so registering the loader above is enough to make it work for .yaif too, in principle.
  # Newer GNOME (glycin-loaders' era) ships this instead of the older gdk-pixbuf-thumbnailer, which
  # make_gdk_pixbuf_plugin's own yaif.thumbnailer still targets for systems that have it. The other
  # glycin-shipped .thumbnailer files all use glycin-thumbnailer's absolute path (the factory spawns
  # it outside an interactive shell's PATH), so this does too -- confirmed NOT sufficient on its own
  # by itself on a real GNOME 50 VM (still no thumbnail); see CLAUDE.md, not chased further.
  local gt_path
  gt_path=$(command -v glycin-thumbnailer 2>/dev/null) || gt_path=
  if [ -n "$gt_path" ]; then
    printf '[Thumbnailer Entry]\nTryExec=%s\nExec=%s --input %%u --output %%o --size %%s\nMimeType=image/x-yaif;\n' \
      "$gt_path" "$gt_path" > "$tmp/yaif-glycin.thumbnailer"
    install_file root "$tmp/yaif-glycin.thumbnailer" "/usr/share/thumbnailers/yaif-glycin.thumbnailer" 644
  fi
  # A working loader is not enough for double-click-to-open: GNOME resolves the default app for a
  # MIME type from mimeapps.list, not from which loader can technically decode it, so Loupe (which
  # decodes .yaif fine once given the file) never gets offered unless set as the default here.
  if [ -f /usr/share/applications/org.gnome.Loupe.desktop ] && command -v xdg-mime > /dev/null 2>&1; then
    run user xdg-mime default org.gnome.Loupe.desktop image/x-yaif
  fi
  ok "glycin loader installed"
}

install_plugins() {
  if [ $plugins = 0 ]; then
    step "Viewer plugins skipped (--no-plugins)"
    return 0
  fi
  step "Viewer plugins (open .yaif files in image viewers, show thumbnails)"
  info "They are built here, for this system's Qt / GNOME. Installing them needs root (system plugin folders)."
  echo

  if command -v cmake >/dev/null 2>&1 && pkg-config --exists Qt6Core 2>/dev/null; then
    info "KDE / Qt: Gwenview, Okular, Krita open .yaif; Dolphin shows thumbnails."
    if ask "Build and install the Qt and KDE plugins?"; then
      cmake_plugin qt "Qt plugin (Gwenview, Okular, Krita)" || true
      if has_kf6kio; then
        if cmake_plugin kde "Dolphin thumbnailer"; then enable_dolphin_thumbnailer; kde_thumb=1; drop_pixbuf_thumbnailer; fi
      else
        info "KF6KIO not found (Fedora: kf6-kio-devel, Debian/Ubuntu: libkf6kio-dev), Dolphin thumbnailer skipped."
      fi
    fi
  else
    info "Qt 6 not found, Qt/KDE plugins skipped."
  fi
  echo

  if pkg-config --exists glycin-2 2>/dev/null; then
    info "GNOME (Loupe, Nautilus): open .yaif via the glycin loader."
    if command -v cargo >/dev/null 2>&1; then
      if ask "Build and install the glycin loader?"; then cargo_glycin_plugin || true; fi
    else
      info "cargo not found (needs Rust), glycin loader skipped."
    fi
  else
    info "GNOME (Loupe, Nautilus): not installed, glycin loader skipped."
  fi
  echo

  if pkg-config --exists gdk-pixbuf-2.0 2>/dev/null; then
    info "GTK / gdk-pixbuf: Eye of GNOME, GIMP and older GTK apps open .yaif."
    if ask "Build and install the gdk-pixbuf loader?"; then make_gdk_pixbuf_plugin || true; fi
  else
    info "gdk-pixbuf not found, GTK loader skipped."
  fi
}

# ---- main ----
case $(uname -s) in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
case $(uname -m) in
  x86_64|amd64) arch=x86_64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

# This script's directory, when it runs from a file (empty for curl | bash).
here=
case ${BASH_SOURCE[0]:-} in */install.sh|install.sh) here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) ;; esac

tmp=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf -- "$tmp"' EXIT

if [ $uninstall = 1 ]; then
  do_uninstall
  exit 0
fi

printf 'YAIF installer  (%s %s, into %s)\n' "$os" "$arch" "$(pretty "$prefix")"

# YAIF was called NOVA up to v2.0.0-beta.6: that install's own manifest-only uninstaller removes it.
old_nova="$prefix/share/nova/install.sh"
if [ -f "$old_nova" ]; then
  step "Removing NOVA, the former name of YAIF ($(pretty "$prefix"))"
  if [ $system = 1 ]; then old_flag=--system; else old_flag="--prefix $prefix"; fi
  # shellcheck disable=SC2086
  NOVA_TEST_ROOT=$TEST_ROOT bash "$old_nova" --uninstall $old_flag ||
    warn "NOVA's uninstaller failed; run it yourself: bash $(pretty "$old_nova") --uninstall"
  # zsh keeps its completion cache while the count of completion files is unchanged: _nova out and
  # _yaif in leaves it the same, so `yaif` would never complete. It is only a cache, rebuilt at start.
  rm -f "${ZDOTDIR:-$HOME}"/.zcompdump*
fi

if [ -n "$from" ]; then
  [ -f "$from" ] || die "no such file: $from"
  archive=$(basename "$from")
  version=$(printf '%s' "$archive" | sed -E "s/^yaif-(.+)-$os-($arch|universal)\\.tar\\.gz\$/\\1/")
  [ -n "$version" ] && [ "$version" != "$archive" ] || die "unexpected archive name: $archive (expected yaif-<version>-$os-$arch.tar.gz)"
  cp "$from" "$tmp/$archive"
  unpack
elif [ -z "$version" ] && [ -x "$here/bin/yaif" ]; then
  # Run from an unpacked release archive: install what sits next to this script.
  step "Installing from $(pretty "$here")"
  version=$("$here/bin/yaif" --version 2>/dev/null | awk 'NR == 1 {print $2}') || true
  [ -n "$version" ] || die "$(pretty "$here/bin/yaif") does not run here: an archive for another OS or architecture?"
  src=$here
else
  find_release
  download
  verify
  unpack
fi
install_bin
install_completion
install_mime
check_libs
install_heic_hdr
install_plugins

step "Done"
ok "yaif $version is installed."
info "Try:  yaif encode photo.jpg          (writes photo.yaif)"
info "      yaif decode photo.yaif photo.png"
info "Manual: https://github.com/$repo/blob/v2/MANUAL.md"
if [ $system = 1 ]; then flag=" --system"
elif [ "$prefix" != "$HOME/.local" ]; then flag=" --prefix $(pretty "$prefix")"
else flag=; fi
info "Uninstall: bash $(pretty "$prefix/share/yaif/install.sh") --uninstall$flag"
