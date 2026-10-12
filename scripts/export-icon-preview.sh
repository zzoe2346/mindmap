#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mindmap_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
mindmap_ictool="${mindmap_developer_dir}/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$mindmap_ictool" ]]; then
    print -u2 "Icon Composer의 ictool을 찾을 수 없습니다. Xcode 설치와 DEVELOPER_DIR를 확인하세요."
    exit 1
fi
mkdir -p Artwork/AppIcon/Preview
"$mindmap_ictool" Artwork/AppIcon/AppIcon.icon --export-image \
    --output-file "$PWD/Artwork/AppIcon/Preview/AppIcon-composer.png" \
    --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 \
    --design-generation 27
xcrun swift -module-cache-path .build/module-cache scripts/icon-preview.swift \
    Artwork/AppIcon/Preview/AppIcon-composer.png Artwork/AppIcon/Preview/AppIcon-web.png
