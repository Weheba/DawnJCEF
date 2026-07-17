#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <cef-binary-distribution> [build-directory]" >&2
  exit 2
fi

CEF_ROOT="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIRECTORY="${2:-$REPOSITORY_ROOT/jcef_build}"
ARTIFACT_DIRECTORY="${3:-$REPOSITORY_ROOT/dawn-artifacts}"

if [[ ! -f "$CEF_ROOT/cmake/FindCEF.cmake" ]]; then
  echo "CEF_ROOT is not a CEF binary distribution: $CEF_ROOT" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode 26 installation must be selected with xcode-select." >&2
  exit 1
fi

cmake -S "$REPOSITORY_ROOT" -B "$BUILD_DIRECTORY" \
  -G Ninja \
  -DPROJECT_ARCH=arm64 \
  -DCMAKE_BUILD_TYPE=Release \
  -DDAWN_NATIVE_CODECS=ON \
  -DCEF_ROOT="$CEF_ROOT"
cmake --build "$BUILD_DIRECTORY" --parallel

"$SCRIPT_DIR/package-macos-runtime.sh" \
  "$BUILD_DIRECTORY" \
  "$CEF_ROOT" \
  "$ARTIFACT_DIRECTORY"

echo "JCEF macOS arm64 build completed at $BUILD_DIRECTORY"
echo "Dawn runtime package completed at $ARTIFACT_DIRECTORY"
