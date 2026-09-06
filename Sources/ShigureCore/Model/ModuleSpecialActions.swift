import Foundation

public enum ModuleSpecialActions {
    public static let pauseSpell = "暂停"
    public static let insertSpellState = "插入法术"
    public static let insertItemState = "插入物品"
    public static let failedSpell = "自动插入法术"
    public static let failedItem = "自动插入物品"
    public static let oneKeySpell = "一键法术"
    public static let oneKeyItem = "一键物品"

    public static let all: [String] = [pauseSpell, failedSpell, failedItem, oneKeySpell]

    public static func isPauseSpell(_ spell: String?) -> Bool { spell?.trimmed() == pauseSpell }
    public static func isFailedSpell(_ spell: String?) -> Bool { spell?.trimmed() == failedSpell }
    public static func isFailedItem(_ spell: String?) -> Bool { spell?.trimmed() == failedItem }
    public static func isOneKeySpell(_ spell: String?) -> Bool { spell?.trimmed() == oneKeySpell }

    /// 旧模块动作中的“插入法术”迁移为“自动插入法术”；“插入物品”迁移为“自动插入物品”。
    public static func normalizeSpellAction(_ spell: String?) -> String {
        let normalized = spell?.trimmed() ?? ""
        if normalized == insertSpellState { return failedSpell }
        if normalized == insertItemState { return failedItem }
        return normalized
    }

    /// 读状态 插入法术（本地索引）→ spellId；要求该技能冷却为 0。
    public static func failedSpell(in state: GameState, map: [Int: Int64]?) -> Int64? {
        let index = state.getInt(insertSpellState)
        guard let map, let spellId = map[index] else { return nil }
        guard let cooldown = state.spells["\(spellId).\(SpellFieldKey.spellCooldown)"] ?? nil else { return nil }
        return cooldown.isZero ? spellId : nil
    }

    /// 读状态 插入物品 → itemId；若有对应物品冷却字段则要求为 0，否则视为可用。
    public static func failedItem(in state: GameState, map: [Int: Int64]?) -> Int64? {
        let index = state.getInt(insertItemState)
        guard let map, let itemId = map[index] else { return nil }
        for (name, tracked) in state.itemIds.sorted(by: { $0.key < $1.key }) where tracked == itemId {
            guard let value = state.getValue(name) else { return nil }
            return value.isZero ? itemId : nil
        }
        return itemId
    }

    /// 读状态 一键辅助 → spellId，不检查冷却。
    public static func oneKeySpell(in state: GameState, map: [Int: Int64]?) -> Int64? {
        let index = state.getInt("一键辅助")
        return map?[index]
    }
}

/// 条件编辑器承载规则级配置的伪字段，不会写入条件表达式。
public enum ShigureConditionFields {
    public static let delay = "$shigure.delay"
    public static let logicDelay = "$shigure.logicDelay"
    public static let continueLogic = "$shigure.continueLogic"
}

/// 值以 spellId 保存、运行时转换为本地技能索引再比较的状态字段。
public enum SpellIdConditionFields {
    public static let oneKeyAssist = "一键辅助"
    public static let insertSpell = "插入法术"
    public static let castingSpell = "施法技能"
    public static let previousSpell = "上个技能"
    public static let names: Set<String> = [oneKeyAssist, insertSpell, castingSpell, previousSpell]

    public static func contains(_ fieldName: String?) -> Bool {
        names.contains(SpellFieldKey.stripRoot(fieldName ?? ""))
    }
}

public enum ItemIdConditionFields {
    public static let insertItem = "插入物品"
    public static let names: Set<String> = [insertItem]

    public static func contains(_ fieldName: String?) -> Bool {
        names.contains(SpellFieldKey.stripRoot(fieldName ?? ""))
    }
}
