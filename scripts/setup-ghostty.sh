#!/usr/bin/env bash
# Vendors libghostty (GhosttyKit) into vendor/ghostty as a thin static library
# plus the C header + module map, so the Xcode project can `import GhosttyKit`.
#
# Source of the library, in order of preference:
#   1. $GHOSTTYKIT  - path to a GhosttyKit.xcframework (e.g. built with
#                     `zig build -Demit-xcframework=true` in a ghostty checkout)
#   2. $GHOSTTY_SRC - path to a ghostty source checkout; we build it with zig
#   3. a known local build on this machine
#   4. upstream ghostty at $GHOSTTY_COMMIT, cloned into ~/projects/ghostty and
#      built with zig
set -euo pipefail
shopt -s inherit_errexit

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/vendor/ghostty"
ARCH="${ARCH:-$(uname -m)}"
# The newest upstream commit whose C API matches the Swift code that calls
# libghostty. Move it forward together with that code.
GHOSTTY_COMMIT=9f2aa93e825735220c44159a2f4856af3ea6e79c

# Ghostty builds with exactly one Zig release, named in its build.zig.zon, so
# the `zig` on PATH is often the wrong one. Homebrew keeps each release as a
# separate keg-only zig@X.Y formula; the newest one is plain `zig`.
zig_for() {
  local version formula
  version="$(sed -n 's/.*minimum_zig_version = "\([0-9]*\.[0-9]*\).*/\1/p' "$1/build.zig.zon")"
  formula="zig@$version"
  brew info "$formula" >/dev/null 2>&1 || formula=zig
  brew list "$formula" >/dev/null 2>&1 || brew install "$formula" >&2
  echo "$(brew --prefix "$formula")/bin/zig"
}

build_xcframework() {
  local zig
  zig="$(zig_for "$1")"
  # Ghostty compiles its Metal shaders, and Xcode ships the Metal compiler as
  # a separate download.
  xcrun -sdk macosx metal --version >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain >&2
  (cd "$1" && "$zig" build -Demit-xcframework=true -Dxcframework-target=native -Demit-macos-app=false -Doptimize=ReleaseFast >&2)
  echo "$1/macos/GhosttyKit.xcframework"
}

find_xcframework() {
  if [ -n "${GHOSTTYKIT:-}" ]; then echo "$GHOSTTYKIT"; return; fi
  if [ -n "${GHOSTTY_SRC:-}" ]; then build_xcframework "$GHOSTTY_SRC"; return; fi
  for candidate in \
    "$HOME/projects/ghostty-remux-upstream-rebuild/macos/GhosttyKit.xcframework" \
    "$HOME/projects/ghostty/macos/GhosttyKit.xcframework"; do
    if [ -d "$candidate" ]; then echo "$candidate"; return; fi
  done
  local src="$HOME/projects/ghostty"
  if [ ! -d "$src" ]; then
    git clone --quiet --no-checkout --filter=blob:none https://github.com/ghostty-org/ghostty.git "$src" >&2
    git -C "$src" checkout --quiet "$GHOSTTY_COMMIT" >&2
  fi
  build_xcframework "$src"
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
