#!/usr/bin/env bash
set -euo pipefail

test "$(uname -m)" = aarch64
root=$(cd "$(dirname "$0")/.." && pwd)
output=${1:-"$root/build/runtime"}
mkdir -p "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git init -q "$work/source"
git -C "$work/source" fetch -q --depth 1 \
  https://github.com/ardera/flutter-pi.git f0b333052f4e71e51f9049e5016082357175057a
git -C "$work/source" checkout -q --detach FETCH_HEAD
cp "$root/native/main.c" "$work/source/src/main.c"
cp "$root/native/controls.inc" "$work/source/src/gizlet_controls.inc"
python3 - "$work/source/src/flutter-pi.c" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
text = source.read_text()
function = "static int flutterpi_run(struct flutterpi *flutterpi) {"
call = "    ok = flutterpi_run(flutterpi);"
assert text.count(function) == text.count(call) == 1
text = text.replace(function, '#include "gizlet_controls.inc"\n\n' + function)
text = text.replace(call, "    gizlet_open_controls(flutterpi);\n" + call)
source.write_text(text)
PY
cmake -S "$work/source" -B "$work/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_SESSION_SWITCHING=OFF -DENABLE_VULKAN=OFF \
  -DBUILD_GSTREAMER_AUDIO_PLAYER_PLUGIN=OFF \
  -DBUILD_GSTREAMER_VIDEO_PLAYER_PLUGIN=OFF \
  -DLTO=OFF
cmake --build "$work/build" --parallel 2

stage="$work/stage"
mkdir -p "$stage/runtime-libs" "$stage/runtime-notices"
install -m 0755 "$work/build/flutter-pi" "$stage/flutter-pi"
strip "$stage/flutter-pi"
cp "$work/source/LICENSE" "$stage/runtime-notices/flutter-pi.txt"
ldd "$stage/flutter-pi" | tee "$work/dependencies"
if grep -q 'not found' "$work/dependencies"; then exit 1; fi
while read -r library dependency; do
  case "$library" in
    ld-linux-*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|\
    libdrm.so.*|libgbm.so.*|libEGL.so.*|libGLdispatch.so.*|libGLESv2.so.*|\
    libsystemd.so.*|libudev.so.*|libcap.so.*|libgcc_s.so.*|libstdc++.so.*|\
    libz.so.*|libzstd.so.*|liblzma.so.*|libselinux.so.*|libpcre2-8.so.*)
      continue ;;
  esac
  install -m 0644 "$dependency" "$stage/runtime-libs/$library"
  resolved=$(realpath "$dependency")
  owner=$(dpkg-query -S "$resolved" "${resolved#/usr}" 2>/dev/null | sed -n '1p' || true)
  test -n "$owner"
  package=${owner%%:*}
  cp -L "/usr/share/doc/$package/copyright" "$stage/runtime-notices/$package.txt"
done < <(awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}' "$work/dependencies")
patchelf --force-rpath --set-rpath '$ORIGIN/runtime-libs' "$stage/flutter-pi"
"$stage/flutter-pi" --help > "$work/help" || true
grep -q 'Run the app in release mode' "$work/help"
python3 - "$stage" "$output/flutter-gizlet-runtime-arm64.zip" <<'PY'
from pathlib import Path
import sys
from zipfile import ZIP_DEFLATED, ZipFile

stage = Path(sys.argv[1])
with ZipFile(sys.argv[2], 'w', ZIP_DEFLATED, allowZip64=False) as archive:
    for file in sorted(stage.rglob('*')):
        if file.is_file():
            archive.write(file, file.relative_to(stage))
PY
