import SwiftUI
import ShigureCore

// ShigureCore 是纯逻辑层，不参与本地化：它的 `displayName` 用于日志与协议文本。
// 界面上要跟随系统语言的名称在这里给出，键仍是中文原文，翻译放在 Localizable.xcstrings。

extension SendMode {
    var localizedName: LocalizedStringResource {
        switch self {
        case .switch: return "开关"
        case .click: return "单击"
        case .hold: return "按住"
        }
    }
}

extension KeyInjectionMode {
    var localizedName: LocalizedStringResource {
        switch self {
        case .process: return "投递到游戏进程"
        case .system: return "系统级输入（需前台）"
        }
    }
}

/// 用运行期得到的中文原文当键去查翻译，查不到就原样返回。
///
/// ShigureCore 是纯逻辑层，不带资源包也不参与本地化，但「关于」页的免责声明、许可证、
/// 致谢等长文都定义在那里。与其把这些文本复制一份到界面层，不如以中文原文为键：
/// 翻译写在 Localizable.xcstrings 里，缺翻译时自然回落到中文。
func localizedReferenceText(_ chinese: String) -> String {
    String(localized: String.LocalizationValue(chinese))
}

/// `AddonSyncResult.summary` 是 Core 拼好的中文整句，整句查不到翻译；
/// 日志要跟界面同语言，所以在界面层按结构化字段重新拼一遍。
func localizedAddonSyncSummary(_ result: AddonSyncResult) -> String {
    if let reason = result.skippedReason { return localizedReferenceText(reason) }
    var text = String(localized: "已复制 \(result.copiedFiles.count) 个文件，\(result.skippedFiles.count) 个相同文件跳过 → \(result.targetRoot?.path ?? "-")")
    if !result.failures.isEmpty {
        let detail = result.failures.prefix(3).map { "\($0.path): \($0.message)" }.joined(separator: "；")
        text += String(localized: "；\(result.failures.count) 个文件失败：\(detail)")
    }
    return text
}
