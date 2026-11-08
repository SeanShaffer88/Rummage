#!/bin/sh
# Builds dist/Rummage-<version>.zip and dist/SHA256SUMS.txt.
# Usage: sh tools/package.sh
set -e
cd "$(dirname "$0")/.."
VER="$(sed -n 's/^## Version:[[:space:]]*//p' Rummage/Rummage.toc | head -1 | tr -d '\r')"
[ -n "$VER" ] || { echo "No '## Version:' in Rummage/Rummage.toc" >&2; exit 1; }
mkdir -p dist
ZIP="dist/Rummage-$VER.zip"
rm -f "$ZIP"
python3 -I - "$ZIP" <<'PY'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("Rummage"):
        dirs.sort()
        z.write(root)
        for f in sorted(files):
            z.write(os.path.join(root, f))
PY
( cd dist && sha256sum "Rummage-$VER.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt )
