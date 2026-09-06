import Foundation

/// 一帧的游戏状态。顶层字段、spells/auras 字典、group[1..30]，以及模块运行时写入的动态字段。
/// 值类型；ModuleLogic 以 inout 方式写入动态字段。
public struct GameState: Sendable, Equatable {
    /// 普通状态字段（按 config 顺序，供状态页展示）。
    public var values: [String: StateValue?]
    public var valueOrder: [String]
    /// 键形如 "8122.cooldown"、"47540.count"。
    public var spells: [String: StateValue?]
    public var spellOrder: [String]
    /// 键形如 "player.450193.value"、"target.harmful.589.value"。
    public var auras: [String: StateValue?]
    public var auraOrder: [String]
    /// 键 "1".."30"，成员字段包含 生命值/职责/驱散/治疗吸收/auras.<id>.value。
    public var group: [String: [String: StateValue?]]
    /// spells 字段 → 冷却/充能/充能层数/施法次数。
    public var spellDisplayTypes: [String: String]
    /// 物品冷却状态字段名 → itemId。
    public var itemIds: [String: Int64]

    // 模块运行时动态字段（C# 中以 "$" 前缀键存于 Values）
    public var dynamicUnits: [String: String?]? = nil
    public var dynamicUnitHealth: [String: StateValue?]? = nil
    public var dynamicCounts: [String: Int]? = nil
    public var dynamicValues: [String: StateValue?]? = nil
    public var dynamicModuleId: String? = nil

    public init() {
        values = [:]
        valueOrder = []
        spells = [:]
        spellOrder = []
        auras = [:]
        auraOrder = []
        group = [:]
        spellDisplayTypes = [:]
        itemIds = [:]
    }

    public mutating func setValue(_ key: String, _ value: StateValue?) {
        if values[key] == nil { valueOrder.append(key) }
        values[key] = .some(value)
    }

    public mutating func setSpell(_ key: String, _ value: StateValue?) {
        if spells[key] == nil { spellOrder.append(key) }
        spells[key] = .some(value)
    }

    public mutating func setAura(_ key: String, _ value: StateValue?) {
        if auras[key] == nil { auraOrder.append(key) }
        auras[key] = .some(value)
    }

    /// C# GameState.GetValue：剥离 state.，路由 spells./spell./auras./aura.，否则顶层字段。
    public func getValue(_ key: String) -> StateValue? {
        var normalized = key.trimmed()
        if let rest = normalized.dropPrefixIgnoringCase("state.") { normalized = rest }
        if let rest = normalized.dropPrefixIgnoringCase("spells.") { return spells[rest] ?? nil }
        if let rest = normalized.dropPrefixIgnoringCase("spell.") { return spells[rest] ?? nil }
        if let rest = normalized.dropPrefixIgnoringCase("auras.") { return auras[rest] ?? nil }
        if let rest = normalized.dropPrefixIgnoringCase("aura.") { return auras[rest] ?? nil }
        return values[normalized] ?? nil
    }

    public func getInt(_ key: String, default defaultValue: Int = 0) -> Int {
        guard let value = getValue(key) else { return defaultValue }
        switch value {
        case .int(let i): return i
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return InvariantNumber.parseInt(s) ?? defaultValue
        case .double: return defaultValue
        }
    }

    public func getBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = getValue(key) else { return defaultValue }
        switch value {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return InvariantNumber.parseInt(s).map { $0 != 0 } ?? defaultValue
        case .double: return defaultValue
        }
    }

    public func groupMember(_ slot: String) -> [String: StateValue?]? {
        group[slot]
    }
}
