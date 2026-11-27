#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
flutter=$1
runtime=$2
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
"$flutter" create --empty --no-pub --platforms=linux --project-name gizlet_smoke "$scratch/app"
"$flutter" pub global activate --source path "$root"
cat > "$scratch/app/gizlet.toml" <<'TOML'
id = "io.gizlet.smoke"
name = "Gizlet Smoke"
version = "0.1.0"
runtime = 1

[[packages]]
target = "aarch64-unknown-linux-gnu"
tier = "lite"
entry = "flutter-pi"
TOML
cd "$scratch/app"
"$flutter" pub global run flutter_gizlet build --arch=arm64 --cpu=generic --release \
  --runtime "$runtime"
package=build/gizlet/io.gizlet.smoke-0.1.0-aarch64-unknown-linux-gnu-lite.gzl
unzip -q "$package" -d "$scratch/gzl"
cd "$scratch/gzl"
shasum -a 256 -c CHECKSUMS >/dev/null
test -x flutter-pi
test -s app.so
test -s libflutter_engine.so
test -s icudtl.dat
test -s AssetManifest.bin
