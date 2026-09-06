# Shigure for macOS

Shigure 的 macOS 原生实现（Swift + SwiftUI）。功能对齐 Windows 版（WinForms / .NET），
但界面与交互按 macOS 习惯重做，不是逐行翻译。

工作方式：读取 Fuyutsui 插件绘制在游戏画面顶部的像素条 → 还原游戏状态 →
按模块规则决定该按哪个键 → 把按键发送给游戏进程，同时提供配置 / 宏 / 模块编辑器与实时诊断界面。

## 环境要求

- macOS 15 或更新（开发验证于 macOS 26）
- Xcode 26，Swift 6（`Package.swift` 为 swift-tools 6.0，启用 strict concurrency）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 《魔兽世界》已安装，并已部署 Fuyutsui 插件（应用会在启动时自动同步）

首次使用先把命令行工具链指向 Xcode：

```sh
sudo xcode-select -s /Applications/Xcode.app
```

## 构建与运行

```sh
scripts/bootstrap.sh --build   # 生成 Xcode 工程并编译
scripts/bootstrap.sh --run     # 编译并启动
scripts/bootstrap.sh --test    # 只跑核心逻辑测试（swift test）
scripts/bootstrap.sh --install # Release 构建并安装到 /Applications
```

日常使用装一次 `--install` 即可，之后从启动台或聚焦打开 `Shigure`。
`--build` / `--run` 产出的是 Debug 构建，放在 `$TMPDIR` 里会被系统定期清理，只适合开发时用。
注意：屏幕录制与辅助功能权限按 App 的路径 + 签名授予，先装到 `/Applications` 再授权，
否则换位置后可能需要重新授权。

`Shigure.xcodeproj` 由 `project.yml` 生成，不纳入版本控制。
`Sources/ShigureApp/` 只属于这个 Xcode 工程、不在 `Package.swift` 里，
所以用只认 SwiftPM 的编辑器打开时，那些文件的 `import ShigureCore` 会被误标为错误；
编辑应用层代码请用 Xcode 打开 `Shigure.xcodeproj`。
仓库位于 iCloud Drive 时 DerivedData 必须放在 iCloud 之外（脚本默认放 `$TMPDIR`），
否则 iCloud 写入的扩展属性会让 `codesign` 失败。

## 工程结构

| 路径 | 说明 |
|---|---|
| `Sources/ShigureCore/` | 纯逻辑，只依赖 Foundation，可独立 `swift test`：Lua 解析与写回、config/keymap 转换、条件与公式求值、模块选择、单位选择、像素解码、运行时、依赖导入、图标包 |
| `Sources/ShigureApp/` | SwiftUI + AppKit 应用层：主窗口、菜单栏图标、各编辑器、平台适配（ScreenCaptureKit 截屏、CGEvent 按键、NSWorkspace 定位游戏） |
| `Resources/` | 内置只读种子数据：`Fuyutsui/`、`config/`、`keymap/`、图标 |
| `Tests/ShigureCoreTests/` | 语义对齐测试，含从 Windows 版复制的真实 fixture |

平台相关能力都在 `ShigureCore` 里以协议表达（`ScreenScanner`、`KeyOutput`、`TriggerKeyState`、
`GameLocator`），应用层提供 macOS 实现，测试里换成假实现，因此核心逻辑不需要真机、真游戏即可验证。

## 用户数据

运行期数据在 `~/Library/Application Support/Shigure/`，首次启动从 App 内置资源播种：

```
Fuyutsui/     插件源文件（config/keymap 由它生成，也会同步到游戏 AddOns 目录）
config/       每职业扫描字段定义（由 Fuyutsui/class/*.lua 生成）
keymap/       每职业按键映射（由 Fuyutsui 宏定义生成）
module/       模块（战斗逻辑规则）
data/         SpellIcons.shgpack 技能与物品图标包
settings.json 应用设置
```

日志在 `~/Library/Logs/Shigure/`。

## 权限

- **屏幕录制**：读取游戏窗口像素，必需
- **辅助功能**：向游戏发送按键，必需
- **输入监控**（可选）：捕获短促的触发键点击

三项都在「通用」页有跳转按钮；未授予时主窗口顶部会常驻横幅。
应用不开启沙盒（需要写入游戏的 `Interface/AddOns` 目录），使用 Hardened Runtime。

## 与 Windows 版的差异

- 无常驻浮动条；改为菜单栏图标 + 单一主窗口（带侧栏）
- 无「关闭时最小化到托盘」选项（macOS 关窗本就不退出）
- 快捷键改为 macOS 习惯：⌘S 保存、⌘N 新建、⌘D 复制、⌘R 刷新、⇧⌘E 开关逻辑、⇧⌘U 更新配置
- 破坏性操作用确认 sheet，字段校验内联显示，不用弹窗串
- 触发键不支持 Option / Command 组合

## 许可证与来源

见应用内「关于」页。
