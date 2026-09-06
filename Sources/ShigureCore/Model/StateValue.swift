import Foundation

/// 运行时状态值。替代 C# 的 `object?`，覆盖像素解码、条件字面量与公式结果会出现的所有类型。
public enum StateValue: Sendable, Equatable, Hashable {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)

    // MARK: 转换（与 C# 各处 switch 语义一致）

    /// GameState.GetInt / UnitSelector.TryInt / ModuleLogic.TryToInt：int、bool→0/1、可解析字符串。
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d):
            guard d.isFinite, abs(d) < 9.2e18 else { return nil }
            return Int(d.rounded(.towardZero))
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return InvariantNumber.parseInt(s)
        }
    }

    /// ModuleConditionEvaluator.TryToDouble。
    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return InvariantNumber.parseDouble(s)
        }
    }

    /// ModuleConditionEvaluator.TryToInt64（double 必须为整值）。
    public var int64Value: Int64? {
        switch self {
        case .int(let i): return Int64(i)
        case .double(let d):
            guard d.isFinite, d == d.rounded(.towardZero), abs(d) < 9.2e18 else { return nil }
            return Int64(d)
        case .bool: return nil
        case .string(let s): return InvariantNumber.parseInt64(s)
        }
    }

    /// GameState.GetBool：bool、int != 0、可解析字符串 != 0。
    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double: return nil
        case .string(let s): return InvariantNumber.parseInt(s).map { $0 != 0 }
        }
    }

    /// ModuleConditionEvaluator.IsTruthy。
    public var isTruthy: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return abs(d) > Double.ulpOfOne
        case .string(let s):
            return !s.isBlank && !s.equalsIgnoringCase("0") && !s.equalsIgnoringCase("false")
        }
    }

    /// ModuleSpecialActions.IsZero。
    public var isZero: Bool {
        switch self {
        case .int(let i): return i == 0
        case .double(let d): return abs(d) < Double.ulpOfOne
        case .bool(let b): return !b
        case .string(let s):
            guard let d = InvariantNumber.parseDouble(s) else { return false }
            return abs(d) < Double.ulpOfOne
        }
    }

    /// ModuleConditionEvaluator.FormatComparable：bool→"true"/"false"，数字不变文化。
    public var comparableText: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return JSONWriter.formatDouble(d)
        case .string(let s): return s
        }
    }

    /// UI 显示（UiTheme.FormatValue）：bool→是/否。
    public var displayText: String {
        switch self {
        case .bool(let b): return b ? "是" : "否"
        case .int(let i): return String(i)
        case .double(let d): return JSONWriter.formatDouble(d)
        case .string(let s): return s
        }
    }
}

extension StateValue: CustomStringConvertible {
    public var description: String { displayText }
}
