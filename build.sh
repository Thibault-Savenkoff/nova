#!/bin/bash
# Builds nova from source (needs the Lisaac compiler) and installs it,
# reusing install.sh for everything after the compile step. For a prebuilt
# binary instead, use install.sh directly (no compiler needed).
# Run from the repository: build.sh [install.sh options...]
set -eu
cd "$(dirname "$0")"

if ! command -v lisaac >/dev/null 2>&1; then
  echo "build.sh: no 'lisaac' compiler found." >&2
  echo "Get it from https://lisaac.org (0.6), or use install.sh instead for a prebuilt binary." >&2
  exit 1
fi

echo "==> Compiling nova (lisaac nova.li -boost)"
lisaac nova.li -boost

case $(uname -s) in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) echo "build.sh: unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case $(uname -m) in
  x86_64|amd64) arch=x86_64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "build.sh: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
archive=$(release/pack.sh "$PWD/nova" "$os" "$arch" "$tmp")

echo "==> Installing"
./install.sh --from "$archive" "$@"
