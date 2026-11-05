#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
LUMA_DEVELOPER_ROOT="$(xcode-select -p)"
LUMA_TEST_FRAMEWORKS="$LUMA_DEVELOPER_ROOT/Library/Developer/Frameworks"
LUMA_TEST_FLAGS=()
# Command Line Tools include Swift Testing but don't add its search paths.
if [[ -d "$LUMA_TEST_FRAMEWORKS/Testing.framework" ]]; then
    LUMA_TEST_FLAGS=(-Xswiftc "-F$LUMA_TEST_FRAMEWORKS" -Xlinker "-F$LUMA_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$LUMA_TEST_FRAMEWORKS" -Xlinker -rpath -Xlinker "$LUMA_DEVELOPER_ROOT/Library/Developer/usr/lib")
fi
swift test --disable-xctest --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security --manifest-cache local "${LUMA_TEST_FLAGS[@]}" "$@"
