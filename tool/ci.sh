#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
flutter="$scratch/flutter/bin/flutter"
dart="$scratch/flutter/bin/dart"
export FLUTTER_SUPPRESS_ANALYTICS=true
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://mirror.sjtu.edu.cn}"

bash "$root/tool/native-dependencies.sh"
bash "$root/tool/build-runtime.sh" "$scratch/runtime"
git clone --depth 1 --branch 3.47.0 https://github.com/flutter/flutter.git "$scratch/flutter"
"$flutter" --version
"$dart" pub get
"$dart" format --output=none --set-exit-if-changed bin lib test
"$dart" analyze
"$dart" test
"$dart" pub publish --dry-run
bash "$root/tool/smoke.sh" "$flutter" "$scratch/runtime/flutter-gizlet-runtime-arm64.zip"
