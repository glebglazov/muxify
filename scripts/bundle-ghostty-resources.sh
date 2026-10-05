#!/usr/bin/env bash
# Xcode build phase: copies Ghostty's runtime resources (terminfo, themes,
# shell integration) into Muxify.app so libghostty can find them. libghostty
# locates them by looking for Contents/Resources/terminfo/78/xterm-ghostty
# next to the running executable.
set -euo pipefail

SRC="${GHOSTTY_APP:-/Applications/Ghostty.app}/Contents/Resources"
DST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

if [ ! -d "$SRC/terminfo" ] || [ ! -d "$SRC/ghostty" ]; then
  echo "warning: Ghostty.app resources not found at $SRC; themes and terminfo will be unavailable"
  exit 0
fi

mkdir -p "$DST"
rsync -a --delete "$SRC/terminfo/" "$DST/terminfo/"
rsync -a --delete --exclude doc "$SRC/ghostty/" "$DST/ghostty/"
