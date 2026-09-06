import Foundation

/// 把 ModuleUnit / ModuleCountField 在当前 group 状态下解析为单位槽位或数量。
/// - 只考虑职责 != 0 的单位（职责缺失/不可解析视为不跳过）；
/// - 最低生命值选择器保留并比较 0 和负生命值；
/// - 生命值数量字段只统计 0 < 生命值 < 阈值；
/// - 按 "1".."30" 升序遍历。
public enum UnitSelector {
    static let defaultThreshold = 100
    typealias Member = [String: StateValue?]

    public static func resolve(_ unit: ModuleUnit, state: GameState) -> String? {
        let group = state.group
        let threshold = resolveThreshold(unit.healthThreshold, unit.healthThresholdField, state, unit.kind.isHealingAbsorbKind ? 0 : defaultThreshold)
        let aura = unit.auraSpellIds?.first
        if unit.kind.requiresAura {
            guard let ids = unit.auraSpellIds, !ids.isEmpty, ids.allSatisfy({ groupContainsAuraField(group, $0) }) else { return nil }
        }
        let role = { (data: Member) in matchesRoleFilter(data, unit.roleFilter, unit.role) }
        switch unit.kind {
        case .lowestHealth:
            return lowestHealth(group, threshold, role)
        case .lowestHealthWithAnyAura:
            guard let ids = unit.auraSpellIds, !ids.isEmpty else { return nil }
            return lowestHealth(group, threshold) { role($0) && hasAnyAura($0, ids) }
        case .lowestHealthWithoutAnyAura:
            guard let ids = unit.auraSpellIds, !ids.isEmpty else { return nil }
            return lowestHealth(group, threshold) { role($0) && !hasAnyAura($0, ids) }
        case .lowestHealthWithoutAura:
            guard let aura else { return nil }
            return lowestHealth(group, threshold) { role($0) && !hasAura($0, aura) }
        case .lowestHealthWithAura:
            guard let aura else { return nil }
            return lowestHealth(group, threshold) { role($0) && hasAura($0, aura) }
        case .lowestHealthWithAuraCount:
            guard let aura, let count = unit.auraCount else { return nil }
            return lowestHealth(group, threshold) { role($0) && auraEquals($0, aura, count) }
        case .unitWithRole:
            guard let r = unit.role else { return nil }
            return unitWithRole(group, r, unit.reverse) { _ in true }
        case .unitWithRoleWithoutAura:
            guard let r = unit.role, let aura else { return nil }
            return unitWithRole(group, r, unit.reverse) { !hasAura($0, aura) }
        case .unitWithAura:
            guard let aura else { return nil }
            return unitWithAura(group, aura, shortest: false)
        case .unitWithAuraShortest:
            guard let aura else { return nil }
            return unitWithAura(group, aura, shortest: true)
        case .unitWithDispelType:
            guard let d = unit.dispelType else { return nil }
            return unitWithDispelType(group, d)
        case .highestHealingAbsorb:
            return highestHealingAbsorb(group, threshold) { _ in true }
        case .highestHealingAbsorbWithAnyAura:
            guard let ids = unit.auraSpellIds, !ids.isEmpty else { return nil }
            return highestHealingAbsorb(group, threshold) { hasAnyAura($0, ids) }
        case .highestHealingAbsorbWithoutAnyAura:
            guard let ids = unit.auraSpellIds, !ids.isEmpty else { return nil }
            return highestHealingAbsorb(group, threshold) { !hasAnyAura($0, ids) }
        case .highestHealingAbsorbWithoutAura:
            guard let aura else { return nil }
            return highestHealingAbsorb(group, threshold) { !hasAura($0, aura) }
        case .highestHealingAbsorbWithAura:
            guard let aura else { return nil }
            return highestHealingAbsorb(group, threshold) { hasAura($0, aura) }
        case .highestHealingAbsorbWithAuraCount:
            guard let aura, let count = unit.auraCount else { return nil }
            return highestHealingAbsorb(group, threshold) { auraEquals($0, aura, count) }
        }
    }

    public static func resolve(_ count: ModuleCountField, state: GameState) -> Int {
        let group = state.group
        let threshold = resolveThreshold(count.healthThreshold, count.healthThresholdField, state, count.kind.isHealingAbsorbKind ? 0 : defaultThreshold)
        if count.kind.requiresAura {
            guard let id = count.auraSpellId, groupContainsAuraField(group, id) else { return 0 }
        }
        let aura = count.auraSpellId
        switch count.kind {
        case .unitsBelowHealth:
            return countUnits(group) { belowThreshold($0, threshold) }
        case .unitsWithoutAuraBelowHealth:
            guard let aura else { return 0 }
            return countUnits(group) { !hasAura($0, aura) && belowThreshold($0, threshold) }
        case .unitsWithAura:
            guard let aura else { return 0 }
            return countUnits(group) { hasAura($0, aura) }
        case .unitsWithAuraBelowHealth:
            guard let aura else { return 0 }
            return countUnits(group) { hasAura($0, aura) && belowThreshold($0, threshold) }
        case .unitsAboveHealingAbsorb:
            return countUnits(group) { aboveHealingAbsorbThreshold($0, threshold) }
        case .unitsWithoutAuraAboveHealingAbsorb:
            guard let aura else { return 0 }
            return countUnits(group) { !hasAura($0, aura) && aboveHealingAbsorbThreshold($0, threshold) }
        case .unitsWithAuraAboveHealingAbsorb:
            guard let aura else { return 0 }
            return countUnits(group) { hasAura($0, aura) && aboveHealingAbsorbThreshold($0, threshold) }
        }
    }

    // MARK: 选择算法

    private static func lowestHealth(_ group: [String: Member], _ threshold: Int, _ predicate: (Member) -> Bool) -> String? {
        var lowestUnit: String?
        var lowestPct = threshold
        for i in 1...30 {
            let key = String(i)
            guard let data = group[key], roleNotZero(data), predicate(data) else { continue }
            guard let pct = tryInt(field(data, "生命值")) else { continue }
            if pct < threshold && pct < lowestPct {
                lowestUnit = key
                lowestPct = pct
            }
        }
        return lowestUnit
    }

    private static func unitWithRole(_ group: [String: Member], _ role: Int, _ reverse: Bool, _ predicate: (Member) -> Bool) -> String? {
        var first: String?
        var last: String?
        for i in 1...30 {
            let key = String(i)
            guard let data = group[key] else { continue }
            guard let r = tryInt(field(data, "职责")), r == role, predicate(data) else { continue }
            if first == nil { first = key }
            last = key
        }
        return reverse ? last : first
    }

    private static func unitWithAura(_ group: [String: Member], _ auraSpellId: Int64, shortest: Bool) -> String? {
        var bestUnit: String?
        var bestDuration = shortest ? Int.max : 0
        for i in 1...30 {
            let key = String(i)
            guard let data = group[key], roleNotZero(data) else { continue }
            guard let duration = tryInt(field(data, SpellFieldKey.auraMember(spellId: auraSpellId))), duration > 0 else { continue }
            let better = shortest ? duration < bestDuration : duration > bestDuration
            if bestUnit == nil || better {
                bestUnit = key
                bestDuration = duration
            }
        }
        return bestUnit
    }

    private static func unitWithDispelType(_ group: [String: Member], _ dispelType: Int) -> String? {
        for i in 1...30 {
            let key = String(i)
            guard let data = group[key], roleNotZero(data) else { continue }
            if let v = tryInt(field(data, "驱散")), v == dispelType { return key }
        }
        return nil
    }

    private static func highestHealingAbsorb(_ group: [String: Member], _ threshold: Int, _ predicate: (Member) -> Bool) -> String? {
        var bestUnit: String?
        var highest = 0
        for i in 1...30 {
            let key = String(i)
            guard let data = group[key], roleNotZero(data), predicate(data) else { continue }
            if let absorb = tryInt(field(data, "治疗吸收")), absorb > 0, absorb > threshold, absorb > highest {
                bestUnit = key
                highest = absorb
            }
        }
        return bestUnit
    }

    private static func countUnits(_ group: [String: Member], _ predicate: (Member) -> Bool) -> Int {
        var count = 0
        for i in 1...30 {
            if let data = group[String(i)], roleNotZero(data), predicate(data) { count += 1 }
        }
        return count
    }

    // MARK: 谓词

    private static func belowThreshold(_ data: Member, _ threshold: Int) -> Bool {
        guard let pct = tryInt(field(data, "生命值")) else { return false }
        return pct > 0 && pct < threshold
    }

    private static func aboveHealingAbsorbThreshold(_ data: Member, _ threshold: Int) -> Bool {
        guard let absorb = tryInt(field(data, "治疗吸收")) else { return false }
        return absorb > threshold
    }

    private static func resolveThreshold(_ fixed: Int?, _ fieldName: String?, _ state: GameState, _ defaultValue: Int) -> Int {
        if let fieldName, !fieldName.isBlank, let dynamic = ConditionEvaluator.resolveInt(state, fieldName) {
            return dynamic
        }
        return fixed ?? defaultValue
    }

    private static func auraEquals(_ data: Member, _ auraSpellId: Int64, _ target: Int) -> Bool {
        tryInt(field(data, SpellFieldKey.auraMember(spellId: auraSpellId))) == target
    }

    private static func matchesRoleFilter(_ data: Member, _ filter: UnitRoleFilterKind?, _ role: Int?) -> Bool {
        guard let filter else { return true }
        guard let role, let actual = tryInt(field(data, "职责")) else { return false }
        return filter == .include ? actual == role : actual != role
    }

    /// 职责为 nil/无法解析时视为不跳过。
    private static func roleNotZero(_ data: Member) -> Bool {
        guard let role = field(data, "职责") else { return true }
        guard let r = tryInt(role) else { return true }
        return r != 0
    }

    private static func hasAura(_ data: Member, _ auraSpellId: Int64) -> Bool {
        guard let n = tryInt(field(data, SpellFieldKey.auraMember(spellId: auraSpellId))) else { return false }
        return n != 0
    }

    private static func hasAnyAura(_ data: Member, _ ids: [Int64]) -> Bool {
        ids.contains { hasAura(data, $0) }
    }

    private static func groupContainsAuraField(_ group: [String: Member], _ spellId: Int64) -> Bool {
        let key = SpellFieldKey.auraMember(spellId: spellId)
        return group.values.contains { $0.keys.contains(key) }
    }

    private static func field(_ data: Member, _ name: String) -> StateValue? {
        data[name] ?? nil
    }

    /// int、long、bool、可解析字符串；double 不接受（与 C# TryInt 一致）。
    static func tryInt(_ value: StateValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .int(let i): return i
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return InvariantNumber.parseInt(s)
        case .double: return nil
        }
    }
}

/// 把动态单位 / 数量字段渲染成人类可读摘要（单位列表与编辑器预览共用）。
public enum UnitSummary {
    public static func describe(_ unit: ModuleUnit, resolveAuraName: ((Int64) -> String?)? = nil) -> String {
        let threshold = describeThreshold(unit.healthThreshold, unit.healthThresholdField, unit.kind.isHealingAbsorbKind ? 0 : 100)
        let aura = unit.auraSpellIds?.first.map { formatAura($0, resolveAuraName) } ?? "?"
        let auras = (unit.auraSpellIds?.isEmpty == false) ? unit.auraSpellIds!.map { formatAura($0, resolveAuraName) }.joined(separator: "/") : "?"
        let dir = unit.reverse ? "逆序" : "正序"
        let role = unit.role.map(String.init) ?? ""
        let body: String
        switch unit.kind {
        case .lowestHealth: body = "血量最低 (<\(threshold))"
        case .lowestHealthWithAnyAura: body = "带任一[\(auras)]且血最低 (<\(threshold))"
        case .lowestHealthWithoutAnyAura: body = "不带任一[\(auras)]且血最低 (<\(threshold))"
        case .lowestHealthWithoutAura: body = "不带[\(aura)]且血最低 (<\(threshold))"
        case .lowestHealthWithAura: body = "带[\(aura)]且血最低 (<\(threshold))"
        case .lowestHealthWithAuraCount: body = "[\(aura)]=\(unit.auraCount.map(String.init) ?? "")且血最低 (<\(threshold))"
        case .unitWithRole: body = "职责=\(role) \(dir)首个"
        case .unitWithRoleWithoutAura: body = "职责=\(role)且不带[\(aura)] \(dir)"
        case .unitWithAura: body = "带[\(aura)] 持续最久"
        case .unitWithAuraShortest: body = "带[\(aura)] 持续最短"
        case .unitWithDispelType: body = "驱散类型=\(unit.dispelType.map(String.init) ?? "")"
        case .highestHealingAbsorb: body = "治疗吸收最高 (>\(threshold))"
        case .highestHealingAbsorbWithAnyAura: body = "带任一[\(auras)]且治疗吸收最高 (>\(threshold))"
        case .highestHealingAbsorbWithoutAnyAura: body = "不带任一[\(auras)]且治疗吸收最高 (>\(threshold))"
        case .highestHealingAbsorbWithoutAura: body = "不带[\(aura)]且治疗吸收最高 (>\(threshold))"
        case .highestHealingAbsorbWithAura: body = "带[\(aura)]且治疗吸收最高 (>\(threshold))"
        case .highestHealingAbsorbWithAuraCount: body = "[\(aura)]=\(unit.auraCount.map(String.init) ?? "")且治疗吸收最高 (>\(threshold))"
        }
        return describeRoleFilter(unit) + body
    }

    public static func describe(_ count: ModuleCountField, resolveAuraName: ((Int64) -> String?)? = nil) -> String {
        let threshold = describeThreshold(count.healthThreshold, count.healthThresholdField, count.kind.isHealingAbsorbKind ? 0 : 100)
        let aura = count.auraSpellId.map { formatAura($0, resolveAuraName) } ?? "?"
        switch count.kind {
        case .unitsBelowHealth: return "血量<\(threshold) 的人数"
        case .unitsWithoutAuraBelowHealth: return "不带[\(aura)]且血<\(threshold) 的人数"
        case .unitsWithAuraBelowHealth: return "带[\(aura)]且血<\(threshold) 的人数"
        case .unitsWithAura: return "带[\(aura)] 的人数"
        case .unitsAboveHealingAbsorb: return "治疗吸收>\(threshold) 的人数"
        case .unitsWithoutAuraAboveHealingAbsorb: return "不带[\(aura)]且治疗吸收>\(threshold) 的人数"
        case .unitsWithAuraAboveHealingAbsorb: return "带[\(aura)]且治疗吸收>\(threshold) 的人数"
        }
    }

    static func formatAura(_ spellId: Int64, _ resolve: ((Int64) -> String?)?) -> String {
        if let name = resolve?(spellId), !name.isBlank { return "\(name) / \(spellId)" }
        return String(spellId)
    }

    static func describeThreshold(_ fixed: Int?, _ field: String?, _ defaultValue: Int) -> String {
        if let field, !field.isBlank { return "动态:\(field.trimmed())" }
        return String(fixed ?? defaultValue)
    }

    static func describeRoleFilter(_ unit: ModuleUnit) -> String {
        guard unit.kind.isLowestHealthKind, let filter = unit.roleFilter else { return "" }
        let role = unit.role.map(String.init) ?? ""
        return filter == .include ? "职责=\(role)且" : "职责!=\(role)且"
    }
}
