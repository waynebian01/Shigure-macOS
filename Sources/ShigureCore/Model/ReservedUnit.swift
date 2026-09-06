import Foundation

/// keymap 中团队槽位 1-30 之外的保留单位。
public enum ReservedUnit {
    public static let none = 0
    public static let player = 31
    public static let target = 32
    public static let focus = 33
    public static let cursor = 34
    public static let mouseover = 35

    public static func displayText(_ unit: Int) -> String {
        switch unit {
        case none: return "无目标"
        case player: return "玩家"
        case target: return "目标"
        case focus: return "焦点"
        case cursor: return "地面"
        case mouseover: return "鼠标"
        default: return String(unit)
        }
    }

    public static func parseDisplayText(_ text: String?) -> Int? {
        let value = text?.trimmed() ?? ""
        switch value {
        case "无目标": return none
        case "玩家": return player
        case "目标": return target
        case "焦点": return focus
        case "地面": return cursor
        case "鼠标": return mouseover
        default: return InvariantNumber.parseInt(value)
        }
    }
}

/// 宏条件在 keymap、模块和界面中统一使用原始标识。
public enum MacroConditionText {
    private static let legacyChannelingUnit = 36
    private static let legacyNoChannelingUnit = 37
    public static let channeling = "channeling"
    public static let noChanneling = "nochanneling"

    /// 兼容旧版误把引导条件写入 unit=36/37 的 keymap 与模块。
    public static func normalizeLegacyUnit(_ unit: Int, _ condition: String?) -> (unit: Int, condition: String) {
        let normalized = normalize(condition)
        switch unit {
        case legacyChannelingUnit:
            return (ReservedUnit.none, normalized.isEmpty ? channeling : normalized)
        case legacyNoChannelingUnit:
            return (ReservedUnit.none, normalized.isEmpty ? noChanneling : normalized)
        default:
            return (unit, normalized)
        }
    }

    public static func normalize(_ text: String?) -> String {
        let parts = (text ?? "")
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { part -> String in
                switch part.lowercased() {
                case "channeling", "引导中": return channeling
                case "nochanneling", "非引导": return noChanneling
                default: return part
                }
            }
        return parts.joined(separator: ", ")
    }

    public static func displayText(_ text: String?) -> String { normalize(text) }
}
