#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <jcef-build-directory> <cef-binary-distribution> <output-directory> [jcef-source-commit]" >&2
  exit 2
fi

BUILD_DIRECTORY="$(cd "$1" && pwd)"
CEF_ROOT="$(cd "$2" && pwd)"
OUTPUT_DIRECTORY="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Full SHA of the DawnJCEF commit the runtime was built from; build_meta.json's jcef_url names it.
# Defaults to this checkout's HEAD, which must have no uncommitted changes to tracked files.
JCEF_SOURCE_COMMIT="${4:-}"
if [[ -z "$JCEF_SOURCE_COMMIT" ]]; then
  JCEF_SOURCE_COMMIT="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
  if [[ -n "$(git -C "$REPOSITORY_ROOT" status --porcelain --untracked-files=no)" ]]; then
    echo "The DawnJCEF checkout has uncommitted changes, so no commit describes this runtime. Commit them first." >&2
    exit 1
  fi
fi
JCEF_SOURCE_COMMIT="$(printf '%s' "$JCEF_SOURCE_COMMIT" | tr 'A-F' 'a-f')"
if [[ ! "$JCEF_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "jcef-source-commit must be a full 40-character commit SHA: $JCEF_SOURCE_COMMIT" >&2
  exit 1
fi

JCEF_COMMIT="d3de827"
UPSTREAM_CEF_VERSION="146.0.10+g8219561+chromium-146.0.7680.179"
RELEASE_TAG="jcef-d3de827+cef-$UPSTREAM_CEF_VERSION"

APP_BUNDLE="$BUILD_DIRECTORY/native/Release/jcef_app.app"
FRAMEWORKS_DIRECTORY="$APP_BUNDLE/Contents/Frameworks"
JCEF_LIBRARY="$APP_BUNDLE/Contents/Java/libjcef.dylib"
CEF_RESOURCES_DIRECTORY="$FRAMEWORKS_DIRECTORY/Chromium Embedded Framework.framework/Resources"
CEF_VERSION_HEADER="$CEF_ROOT/include/cef_version.h"
CEF_BUILD_MARKER="$CEF_ROOT/dawn-codec-build.properties"

if [[ ! -f "$CEF_ROOT/cmake/FindCEF.cmake" || ! -f "$CEF_VERSION_HEADER" ]]; then
  echo "CEF_ROOT is not a CEF binary distribution: $CEF_ROOT" >&2
  exit 1
fi
if [[ ! -f "$CEF_BUILD_MARKER" ]]; then
  echo "CEF_ROOT is not a Dawn native-codec distribution: $CEF_ROOT" >&2
  exit 1
fi

# Each Dawn codec revision pins one CEF version (see CMakeLists.txt). native-codecs.5 is the
# first macOS build.
if grep -Fqx "codec.revision=native-codecs.5" "$CEF_BUILD_MARKER"; then
  CODEC_REVISION="native-codecs.5"
  NATIVE_CEF_VERSION="146.0.28+g2c074f3+chromium-146.0.7680.179"
else
  echo "CEF_ROOT marker names no known Dawn codec revision: $CEF_ROOT" >&2
  exit 1
fi
if ! grep -Fqx "#define CEF_VERSION \"$NATIVE_CEF_VERSION\"" "$CEF_VERSION_HEADER"; then
  echo "CEF_ROOT has an unexpected CEF version: $CEF_ROOT" >&2
  exit 1
fi

# The platform follows the architecture libjcef.dylib was built for.
if [[ ! -f "$JCEF_LIBRARY" ]]; then
  echo "Required JCEF runtime path is missing: $JCEF_LIBRARY" >&2
  exit 1
fi
case "$(lipo -archs "$JCEF_LIBRARY")" in
  arm64) MACHO_ARCH="arm64"; PLATFORM="macosx-arm64" ;;
  x86_64) MACHO_ARCH="x86_64"; PLATFORM="macosx-amd64" ;;
  *)
    echo "libjcef.dylib must be a single arm64 or x86_64 slice: $(lipo -archs "$JCEF_LIBRARY")" >&2
    exit 1
    ;;
esac
BASENAME="jcef-natives-$PLATFORM-jcef-$JCEF_COMMIT+cef-$NATIVE_CEF_VERSION+$CODEC_REVISION"
for entry in \
  "codec.revision=$CODEC_REVISION" \
  "cef.source.commit=82195616d8405e6081a0d90924707b82aa9e4141" \
  "chromium.version=146.0.7680.179" \
  "ffmpeg.branding=Chromium" \
  "media.use-openh264=false"; do
  if ! grep -Fqx "$entry" "$CEF_BUILD_MARKER"; then
    echo "CEF_ROOT marker is missing '$entry': $CEF_ROOT" >&2
    exit 1
  fi
done

for path in \
  "$FRAMEWORKS_DIRECTORY/Chromium Embedded Framework.framework" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper.app" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper (Alerts).app" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper (GPU).app" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper (Plugin).app" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper (Renderer).app" \
  "$JCEF_LIBRARY" \
  "$CEF_RESOURCES_DIRECTORY/resources.pak" \
  "$CEF_RESOURCES_DIRECTORY/icudtl.dat"; do
  if [[ ! -e "$path" ]]; then
    echo "Required JCEF runtime path is missing: $path" >&2
    exit 1
  fi
done

shopt -s nullglob
CEF_SNAPSHOT_FILES=("$CEF_RESOURCES_DIRECTORY"/v8_context_snapshot*.bin)
if [[ -f "$CEF_RESOURCES_DIRECTORY/snapshot_blob.bin" ]]; then
  CEF_SNAPSHOT_FILES+=("$CEF_RESOURCES_DIRECTORY/snapshot_blob.bin")
fi
if (( ${#CEF_SNAPSHOT_FILES[@]} == 0 )); then
  echo "Required CEF snapshot resource is missing: $CEF_RESOURCES_DIRECTORY" >&2
  exit 1
fi

for binary in \
  "$JCEF_LIBRARY" \
  "$FRAMEWORKS_DIRECTORY/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
  "$FRAMEWORKS_DIRECTORY/jcef Helper.app/Contents/MacOS/jcef Helper"; do
  if ! lipo -archs "$binary" | tr ' ' '\n' | grep -Fqx "$MACHO_ARCH"; then
    echo "Required runtime binary is not $MACHO_ARCH: $binary" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd "$OUTPUT_DIRECTORY" && pwd)"
STAGING_DIRECTORY="$OUTPUT_DIRECTORY/staging-$PLATFORM"
case "$STAGING_DIRECTORY" in
  "$OUTPUT_DIRECTORY"/*) ;;
  *)
    echo "Refusing to clean staging path outside the artifact directory: $STAGING_DIRECTORY" >&2
    exit 1
    ;;
esac
rm -rf "$STAGING_DIRECTORY"
mkdir -p "$STAGING_DIRECTORY"

cp -R "$FRAMEWORKS_DIRECTORY/Chromium Embedded Framework.framework" "$STAGING_DIRECTORY/"
cp -R "$FRAMEWORKS_DIRECTORY"/jcef\ Helper*.app "$STAGING_DIRECTORY/"
cp "$JCEF_LIBRARY" "$STAGING_DIRECTORY/"
cp "$REPOSITORY_ROOT/LICENSE.txt" "$STAGING_DIRECTORY/LICENSE.txt"
cp "$REPOSITORY_ROOT/third_party/jogamp/gluegen.LICENSE.txt" "$STAGING_DIRECTORY/gluegen.LICENSE.txt"
cp "$REPOSITORY_ROOT/third_party/jogamp/jogl.LICENSE.txt" "$STAGING_DIRECTORY/jogl.LICENSE.txt"
cp "$CEF_ROOT/README.txt" "$STAGING_DIRECTORY/README.txt"

cat >"$STAGING_DIRECTORY/build_meta.json" <<EOF
{
  "jcef_url": "https://github.com/Weheba/DawnJCEF/commit/$JCEF_SOURCE_COMMIT",
  "release_tag": "$RELEASE_TAG",
  "platform": "$PLATFORM",
  "cef_source": "https://github.com/Weheba/DawnCEFSource",
  "cef_version": "$NATIVE_CEF_VERSION",
  "dawn_codec_revision": "$CODEC_REVISION"
}
EOF

TAR_NAME="$BASENAME.tar.gz"
JAR_NAME="$BASENAME.jar"
TAR_PATH="$OUTPUT_DIRECTORY/$TAR_NAME"
JAR_PATH="$OUTPUT_DIRECTORY/$JAR_NAME"

tar -C "$STAGING_DIRECTORY" -czf "$TAR_PATH" .
rm -f "$JAR_PATH"
(cd "$OUTPUT_DIRECTORY" && jar --create --file "$JAR_NAME" "$TAR_NAME")
shasum -a 256 "$JAR_PATH" >"$JAR_PATH.sha256"

ls -lh "$JAR_PATH" "$JAR_PATH.sha256"
