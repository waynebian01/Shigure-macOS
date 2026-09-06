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
  --install)
    # Release 构建并安装到 /Applications，之后可从启动台/聚焦直接打开。
    # 必须先退出正在运行的实例，否则替换正在使用的 bundle 会留下损坏的副本。
    xcodebuild -project Shigure.xcodeproj -scheme Shigure -configuration Release -derivedDataPath "$DD" build | tail -1
    pkill -x Shigure 2>/dev/null || true
    sleep 1
    rm -rf /Applications/Shigure.app
    ditto "$DD/Build/Products/Release/Shigure.app" /Applications/Shigure.app
    xattr -cr /Applications/Shigure.app 2>/dev/null || true
    codesign --verify --strict /Applications/Shigure.app
    echo "已安装: /Applications/Shigure.app"
    ;;
esac
