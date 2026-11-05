#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local
APP="$PWD/dist/Luma.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Luma "$APP/Contents/MacOS/Luma.new"
mv -f "$APP/Contents/MacOS/Luma.new" "$APP/Contents/MacOS/Luma"
for bundle in .build/release/*.bundle; do
    [[ -d "$bundle" ]] && ditto "$bundle" "$APP/Contents/Resources/${bundle:t}"
done
cp scripts/Info.plist "$APP/Contents/Info.plist"
swift -module-cache-path "$PWD/.build/swift-module-cache" scripts/make-icon.swift "$PWD/.build/Luma.iconset"
cp .build/Luma.icns "$APP/Contents/Resources/Luma.icns"
codesign --force --deep --sign - "$APP"
print "Built $APP"
