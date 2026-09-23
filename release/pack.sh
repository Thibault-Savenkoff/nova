#!/bin/bash
# Builds a release archive: nova-<version>-<os>-<arch>.tar.gz + its .sha256,
# from a pre-built nova binary and the tracked files install.sh needs
# (install.sh itself, completions, libnova sources, plugin sources, docs).
# Used both by the GitHub Actions release job and by test/install.sh to
# build a fake local release.
#
# Usage: release/pack.sh <nova-binary> <os> <arch> <out-dir>
set -e
cd "$(dirname "$0")/.."

[ $# -eq 4 ] || { echo "usage: release/pack.sh <nova-binary> <os> <arch> <out-dir>" >&2; exit 1; }
bin=$1 os=$2 arch=$3 out=$4
[ -f "$bin" ] || { echo "release/pack.sh: no such binary: $bin" >&2; exit 1; }

version=$(sed -n 's/.*- version:String := "\(.*\)"/\1/p' nova.li)
[ -n "$version" ] || { echo "release/pack.sh: version not found in nova.li" >&2; exit 1; }
name="nova-$version-$os-$arch"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
dest="$stage/$name"
mkdir -p "$dest/bin"
install -m 755 "$bin" "$dest/bin/nova"

# In a clone, only tracked files: that skips build artifacts (plugins/*/target, *.so, ...). GitHub's
# "Source code" archive has no .git, and there `git ls-files` fails into an empty pipe -- the
# package then held bin/ alone and build.sh installed that without a word. A fresh extract has no
# build artifacts to skip, so plain find is right there.
paths="install.sh completions libnova libheif-gainmap plugins/qt plugins/kde plugins/glycin plugins/gdk-pixbuf
       plugins/mime README.md MANUAL.md FORMAT.md LICENSE"
# shellcheck disable=SC2086
if [ -e .git ]; then git ls-files $paths; else find $paths -type f; fi |
while read -r f; do
  mkdir -p "$dest/$(dirname "$f")"
  cp "$f" "$dest/$f"
done

mkdir -p "$out"
tar -C "$stage" -czf "$out/$name.tar.gz" "$name"
(cd "$out" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
echo "$out/$name.tar.gz"
