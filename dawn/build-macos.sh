#!/usr/bin/env bash
set -euo pipefail

# Builds JCEF against a Dawn native-codec CEF binary distribution and packages
# the launcher runtime jar. The architecture follows the distribution:
# DAWN_MAC_ARCH=arm64 (default) or x86_64, which cross-compiles on Apple silicon.
# Needs cmake, ninja and ant (JCEF bundles its Java test app) on PATH.

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <cef-binary-distribution> [build-directory] [artifact-directory]" >&2
  exit 2
fi

CEF_ROOT="$(cd "$1" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIRECTORY="${2:-$REPOSITORY_ROOT/jcef_build}"
ARTIFACT_DIRECTORY="${3:-$REPOSITORY_ROOT/dawn-artifacts}"
MAC_ARCH="${DAWN_MAC_ARCH:-arm64}"

case "$MAC_ARCH" in
  arm64 | x86_64) ;;
  *)
    echo "DAWN_MAC_ARCH must be arm64 or x86_64: $MAC_ARCH" >&2
    exit 1
    ;;
esac

if [[ ! -f "$CEF_ROOT/cmake/FindCEF.cmake" ]]; then
  echo "CEF_ROOT is not a CEF binary distribution: $CEF_ROOT" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode 26 installation must be selected with xcode-select." >&2
  exit 1
fi

for tool in cmake ninja ant; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool must be on PATH." >&2
    exit 1
  fi
done

# macOS ships python3 but no `python`, which CMake's FindPythonInterp looks for. The pinned clang-format
# downloader needs Python 3.11 or older; PYTHON_EXECUTABLE selects a specific interpreter.
PYTHON_EXECUTABLE="${PYTHON_EXECUTABLE:-$(command -v python3 || true)}"
if [[ -z "$PYTHON_EXECUTABLE" ]]; then
  echo "python3 must be on PATH, or set PYTHON_EXECUTABLE." >&2
  exit 1
fi
export PYTHON_EXECUTABLE

# The pinned clang-format downloader imports six from the vendored gsutil.
VENDORED_SIX="$REPOSITORY_ROOT/tools/buildtools/external_bin/gsutil/gsutil_4.68/gsutil/third_party/six"
export PYTHONPATH="$VENDORED_SIX${PYTHONPATH:+:$PYTHONPATH}"

cmake -S "$REPOSITORY_ROOT" -B "$BUILD_DIRECTORY" \
  -G Ninja \
  -DPROJECT_ARCH="$MAC_ARCH" \
  -DCMAKE_BUILD_TYPE=Release \
  -DDAWN_NATIVE_CODECS=ON \
  -DCEF_ROOT="$CEF_ROOT"
cmake --build "$BUILD_DIRECTORY" --parallel

bash "$SCRIPT_DIR/package-macos-runtime.sh" \
  "$BUILD_DIRECTORY" \
  "$CEF_ROOT" \
  "$ARTIFACT_DIRECTORY"

echo "JCEF macOS $MAC_ARCH build completed at $BUILD_DIRECTORY"
echo "Dawn runtime package completed at $ARTIFACT_DIRECTORY"
