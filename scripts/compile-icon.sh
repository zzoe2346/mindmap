#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mkdir -p .build/icon
xcrun actool --compile .build/icon --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist .build/icon/icon-info.plist \
    --output-format human-readable-text --warnings --errors Artwork/AppIcon/AppIcon.icon
