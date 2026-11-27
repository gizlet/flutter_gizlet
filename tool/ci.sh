#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
flutter="$scratch/flutter/bin/flutter"
dart="$scratch/flutter/bin/dart"
export FLUTTER_SUPPRESS_ANALYTICS=true

bash "$root/tool/native-dependencies.sh" aria2
bash "$root/tool/build-runtime.sh" "$scratch/runtime"
git clone --depth 1 --branch 3.47.0 https://github.com/flutter/flutter.git "$scratch/flutter"
engine=$(cat "$scratch/flutter/bin/internal/engine.version")
sdk_cache="$scratch/flutter/bin/cache"
mkdir -p "$sdk_cache"
aria2c --dir="$sdk_cache" --out=dart-sdk-linux-arm64.zip \
  --split=8 --max-connection-per-server=8 --min-split-size=4M \
  --max-tries=12 --retry-wait=3 --connect-timeout=20 --timeout=30 \
  --summary-interval=30 --download-result=hide \
  --checksum=sha-256=d4fd5a3b84435073018be7175a31abffbaf6317a082981d7639350bcc4ea8f73 \
  "https://storage.googleapis.com/flutter_infra_release/flutter/$engine/dart-sdk-linux-arm64.zip"
unzip -q "$sdk_cache/dart-sdk-linux-arm64.zip" -d "$sdk_cache"
printf '%s\n' "$engine" > "$sdk_cache/engine-dart-sdk.stamp"
"$flutter" --version
"$dart" pub get
"$dart" format --output=none --set-exit-if-changed bin lib test
"$dart" analyze
"$dart" test
"$dart" pub publish --dry-run
bash "$root/tool/smoke.sh" "$flutter" "$scratch/runtime/flutter-gizlet-runtime-arm64.zip"
