#!/usr/bin/env bash
# Builds dgq-win.zip from the win/ scripts.
set -euo pipefail
cd -- "$(dirname -- "$(readlink -f -- "$0")")"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir "$tmp/dgq-win"
cp win/Play.bat win/play.ps1 win/README.txt "$tmp/dgq-win/"
rm -f dgq-win.zip
(cd "$tmp" && zip -qr - dgq-win) >dgq-win.zip
echo "built dgq-win.zip"
