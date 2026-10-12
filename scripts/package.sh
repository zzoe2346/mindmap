#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
mindmap_sdk=$(xcrun --sdk macosx --show-sdk-path)
mindmap_sdk_version=$(xcrun --sdk macosx --show-sdk-version)
mindmap_options=(-c release --disable-sandbox --triple "$mindmap_triple" --sdk "$mindmap_sdk" -Xlinker -platform_version -Xlinker macos -Xlinker 26.0 -Xlinker "$mindmap_sdk_version")
xcrun swift build "${mindmap_options[@]}"
mindmap_bin=$(xcrun swift build "${mindmap_options[@]}" --show-bin-path)
mkdir -p dist/mindmap.app/Contents/MacOS dist/mindmap.app/Contents/Resources
cp "$mindmap_bin/Mindmap" dist/mindmap.app/Contents/MacOS/Mindmap
cp AppResources/Info.plist dist/mindmap.app/Contents/Info.plist
if [[ -f AppResources/AppIcon.icns ]]; then cp AppResources/AppIcon.icns dist/mindmap.app/Contents/Resources/; fi
plutil -replace DTSDKName -string "macosx$mindmap_sdk_version" dist/mindmap.app/Contents/Info.plist
codesign --force --deep --sign - dist/mindmap.app
codesign --verify --deep --strict dist/mindmap.app
printf '앱 생성 완료: %s/dist/mindmap.app\n' "$PWD"
