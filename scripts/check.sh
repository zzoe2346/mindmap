#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
xcrun swift test --disable-sandbox --triple "$mindmap_triple"
./scripts/package.sh
