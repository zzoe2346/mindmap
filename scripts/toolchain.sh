#!/bin/zsh
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mindmap_triple="$(uname -m)-apple-macosx26.0"
