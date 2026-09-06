#!/bin/zsh
# 生成 Xcode 工程并构建。首次使用前：
#   sudo xcode-select -s /Applications/Xcode.app   （或在命令前加 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer）
#   brew install xcodegen
# 注意：仓库位于 iCloud Drive 时，DerivedData 必须放在 iCloud 之外，否则 codesign 会因扩展属性失败。
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DD="${SHIGURE_DERIVED_DATA:-${TMPDIR:-/tmp}/Shigure-DerivedData}"
xcodegen generate
case "${1:-}" in
  --build)
    xcodebuild -project Shigure.xcodeproj -scheme Shigure -configuration Debug -derivedDataPath "$DD" build | tail -3
    echo "App: $DD/Build/Products/Debug/Shigure.app"
    ;;
  --run)
    xcodebuild -project Shigure.xcodeproj -scheme Shigure -configuration Debug -derivedDataPath "$DD" build | tail -1
    open "$DD/Build/Products/Debug/Shigure.app"
    ;;
  --test)
    swift test
    ;;
esac
