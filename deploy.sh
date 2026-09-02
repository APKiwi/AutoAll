#!/bin/bash
# Push this repo's mod tree into the Workshop folder the in-game uploader reads.
# The repo is the source of truth. The Workshop folder is a build output.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="$HOME/Zomboid/Workshop/AutoAllFixed"
rsync -a --delete \
    --exclude .git --exclude '*.md' --exclude deploy.sh --exclude .gitignore --exclude .DS_Store \
    "$SRC/" "$DST/"
echo "deployed $(git -C "$SRC" rev-parse --short HEAD) -> $DST"
