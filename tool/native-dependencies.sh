#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update -q
sudo apt-get install -yq --no-install-recommends \
  build-essential cmake pkg-config libdrm-dev libgbm-dev libsystemd-dev \
  libinput-dev libxkbcommon-dev libudev-dev libegl-dev libgles-dev \
  patchelf unzip "$@"
