#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <jcef-build-directory> <cef-binary-distribution> <output-directory>" >&2
  exit 2
fi

BUILD_DIRECTORY="$(cd "$1" && pwd)"
CEF_ROOT="$(cd "$2" && pwd)"
OUTPUT_DIRECTORY="$3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

JCEF_COMMIT="d3de827"
CEF_VERSION="146.0.10+g8219561+chromium-146.0.7680.179"
CODEC_REVISION="native-codecs.1"
RELEASE_TAG="jcef-d3de827+cef-$CEF_VERSION"
PLATFORM="macosx-arm64"
BASENAME="jcef-natives-$PLATFORM-jcef-$JCEF_COMMIT+cef-$CEF_VERSION+$CODEC_REVISION"

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
if ! grep -Fqx "#define CEF_VERSION \"$CEF_VERSION\"" "$CEF_VERSION_HEADER"; then
  echo "CEF_ROOT has an unexpected CEF version: $CEF_ROOT" >&2
  exit 1
fi
if [[ ! -f "$CEF_BUILD_MARKER" ]]; then
  echo "CEF_ROOT is not a Dawn native-codec distribution: $CEF_ROOT" >&2
  exit 1
fi
for entry in \
  "codec.revision=$CODEC_REVISION" \
  "cef.source.commit=82195616d8405e6081a0d90924707b82aa9e4141" \
  "chromium.version=146.0.7680.179" \
  "ffmpeg.branding=Chromium"; do
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
  if ! lipo -archs "$binary" | tr ' ' '\n' | grep -Fqx arm64; then
    echo "Required runtime binary is not arm64: $binary" >&2
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
  "jcef_url": "https://github.com/Weheba/DawnJCEF/commit/d3de8278626c160d4631db3fda2df7b77cc1e5c4",
  "release_tag": "$RELEASE_TAG",
  "platform": "$PLATFORM",
  "cef_source": "https://github.com/Weheba/DawnCEFSource",
  "cef_version": "$CEF_VERSION",
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
