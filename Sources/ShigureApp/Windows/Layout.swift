import SwiftUI

/// 主窗口的宽度预算，单一来源。
///
/// 为什么需要一份「预算」：`NavigationSplitView` 在 macOS 上不会为侧栏保底 —— 详情区报多大
/// 的最小宽度，它就把侧栏挤多窄，直到侧栏被完全推出窗口左边（用户看到的现象就是「侧边栏
/// 不见了」，而且没有任何提示）。详情区里的 `HSplitView` 也一样：装不下就整体左移而不是压缩。
///
/// 所以这里的规则是：
/// 1. 每一页的最小宽度都必须**真的**能装下它的内容（固定列宽合计 + 内边距），不能靠"希望"；
/// 2. `windowMin` = 侧栏理想宽 + 最宽那一页的最小宽 + 余量，并作为窗口的硬下限；
/// 3. 页面里任何「按最长一项撑开」的控件（弹出菜单尤其典型）都要显式给 `minWidth`，
///    否则它的固有宽度会悄悄进入最小宽度，把预算顶穿。
enum Layout {
    // MARK: 侧栏

    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 200
    static let sidebarMax: CGFloat = 260

    // MARK: 分栏编辑器（配置页 / 宏页）

    static let listMin: CGFloat = 150
    static let listIdeal: CGFloat = 170
    static let listMax: CGFloat = 220

    /// 编辑器内部再分栏时两栏各自的下限。
    static let innerPrimaryMin: CGFloat = 440
    static let innerSecondaryMin: CGFloat = 260

    /// 右侧主体：要放得下内部分栏的两栏 + 分隔条 + 内边距。
    static let editorMin: CGFloat = innerPrimaryMin + innerSecondaryMin + 20   // 720

    // MARK: 模块页

    static let moduleListMin: CGFloat = 190
    static let moduleListIdeal: CGFloat = 210
    static let moduleListMax: CGFloat = 220

    /// 规则表固定列合计：启用 36 + 图标 32 + 技能 140 + 目标 104 + 宏条件 104 + 条件 54 +
    /// 操作 88 = 558，加 6 个 8 pt 列间距 = 606，加左右 16 pt 内边距和列表自身的行内缩进。
    static let moduleEditorMin: CGFloat = 640

    // MARK: 汇总

    /// 详情区的最小宽度 = 最宽的那一页。
    static let detailMin: CGFloat = max(listMin + editorMin, moduleListMin + moduleEditorMin)

    /// 窗口最小宽度：侧栏理想宽 + 详情区最小宽 + 余量。低于它侧栏就会被挤出窗口，
    /// 所以这个值直接给到 `NSWindow.contentMinSize`（见 ShigureApp 的 `.frame(minWidth:)`）。
    static let windowMin: CGFloat = sidebarIdeal + detailMin + 250
    static let windowMinHeight: CGFloat = 600
}
