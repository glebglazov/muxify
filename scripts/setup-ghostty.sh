#!/usr/bin/env bash
# Vendors libghostty (GhosttyKit) into vendor/ghostty as a thin static library
# plus the C header + module map, so the Xcode project can `import GhosttyKit`.
#
# Source of the library, in order of preference:
#   1. $GHOSTTYKIT  - path to a GhosttyKit.xcframework (e.g. built with
#                     `zig build -Demit-xcframework=true` in a ghostty checkout)
#   2. $GHOSTTY_SRC - path to a ghostty source checkout; we build it with zig
#   3. a known local build on this machine
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/vendor/ghostty"
ARCH="${ARCH:-$(uname -m)}"

find_xcframework() {
  if [ -n "${GHOSTTYKIT:-}" ]; then echo "$GHOSTTYKIT"; return; fi
  if [ -n "${GHOSTTY_SRC:-}" ]; then
    (cd "$GHOSTTY_SRC" && zig build -Demit-xcframework=true -Dxcframework-target=native -Doptimize=ReleaseFast >&2)
    echo "$GHOSTTY_SRC/macos/GhosttyKit.xcframework"; return
  fi
  for candidate in \
    "$HOME/projects/ghostty-remux-upstream-rebuild/macos/GhosttyKit.xcframework" \
    "$HOME/projects/ghostty/macos/GhosttyKit.xcframework"; do
    if [ -d "$candidate" ]; then echo "$candidate"; return; fi
  done
  echo "No GhosttyKit.xcframework found. Set GHOSTTYKIT=/path/to/GhosttyKit.xcframework or GHOSTTY_SRC=/path/to/ghostty" >&2
  exit 1
}

XCF="$(find_xcframework)"
SLICE="$(find "$XCF" -maxdepth 1 -type d -name 'macos-*' | head -1)"
[ -n "$SLICE" ] || { echo "No macOS slice in $XCF" >&2; exit 1; }
LIB="$(find "$SLICE" -maxdepth 1 -name '*.a' | head -1)"

echo "Using $LIB"
rm -rf "$OUT" && mkdir -p "$OUT/lib" "$OUT/include"
if lipo -info "$LIB" | grep -q 'Architectures in the fat file'; then
  lipo "$LIB" -thin "$ARCH" -output "$OUT/lib/libghostty.a"
else
  cp "$LIB" "$OUT/lib/libghostty.a"
fi
cp "$SLICE/Headers/ghostty.h" "$OUT/include/ghostty.h"
cat > "$OUT/include/module.modulemap" <<'MAP'
module GhosttyKit {
    umbrella header "ghostty.h"
    export *
}
MAP
du -sh "$OUT/lib/libghostty.a"
