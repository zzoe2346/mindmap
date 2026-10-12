#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
