import Foundation

/// 动态单位选择器类型（与 C# UnitSelectorKind 名称一致，JSON 以名称字符串保存）。
public enum UnitSelectorKind: String, Sendable, CaseIterable, Codable {
    case lowestHealth = "LowestHealth"
    case lowestHealthWithAnyAura = "LowestHealthWithAnyAura"
    case lowestHealthWithoutAnyAura = "LowestHealthWithoutAnyAura"
    case lowestHealthWithoutAura = "LowestHealthWithoutAura"
    case lowestHealthWithAura = "LowestHealthWithAura"
    case lowestHealthWithAuraCount = "LowestHealthWithAuraCount"
    case unitWithRole = "UnitWithRole"
    case unitWithRoleWithoutAura = "UnitWithRoleWithoutAura"
    case unitWithAura = "UnitWithAura"
    case unitWithAuraShortest = "UnitWithAuraShortest"
    case unitWithDispelType = "UnitWithDispelType"
    case highestHealingAbsorb = "HighestHealingAbsorb"
    case highestHealingAbsorbWithAnyAura = "HighestHealingAbsorbWithAnyAura"
    case highestHealingAbsorbWithoutAnyAura = "HighestHealingAbsorbWithoutAnyAura"
    case highestHealingAbsorbWithoutAura = "HighestHealingAbsorbWithoutAura"
    case highestHealingAbsorbWithAura = "HighestHealingAbsorbWithAura"
    case highestHealingAbsorbWithAuraCount = "HighestHealingAbsorbWithAuraCount"

    public var isHealingAbsorbKind: Bool {
        switch self {
        case .highestHealingAbsorb, .highestHealingAbsorbWithAnyAura, .highestHealingAbsorbWithoutAnyAura,
             .highestHealingAbsorbWithoutAura, .highestHealingAbsorbWithAura, .highestHealingAbsorbWithAuraCount:
            return true
        default: return false
        }
    }

    public var isLowestHealthKind: Bool {
        switch self {
        case .lowestHealth, .lowestHealthWithAnyAura, .lowestHealthWithoutAnyAura,
             .lowestHealthWithoutAura, .lowestHealthWithAura, .lowestHealthWithAuraCount:
            return true
        default: return false
        }
    }

    public var requiresAura: Bool {
        switch self {
        case .lowestHealth, .unitWithRole, .unitWithDispelType, .highestHealingAbsorb: return false
        default: return true
        }
    }

    public var usesAuraList: Bool {
        switch self {
        case .lowestHealthWithAnyAura, .lowestHealthWithoutAnyAura, .highestHealingAbsorbWithAnyAura, .highestHealingAbsorbWithoutAnyAura:
            return true
        default: return false
        }
    }
}

public enum UnitRoleFilterKind: String, Sendable, CaseIterable, Codable {
    case include = "Include"
    case exclude = "Exclude"
}

public enum CountKind: String, Sendable, CaseIterable, Codable {
    case unitsBelowHealth = "UnitsBelowHealth"
    case unitsWithoutAuraBelowHealth = "UnitsWithoutAuraBelowHealth"
    case unitsWithAura = "UnitsWithAura"
    case unitsWithAuraBelowHealth = "UnitsWithAuraBelowHealth"
    case unitsAboveHealingAbsorb = "UnitsAboveHealingAbsorb"
    case unitsWithoutAuraAboveHealingAbsorb = "UnitsWithoutAuraAboveHealingAbsorb"
    case unitsWithAuraAboveHealingAbsorb = "UnitsWithAuraAboveHealingAbsorb"
    case averageHealth = "AverageHealth"
    case averageHealthWithAura = "AverageHealthWithAura"
    case averageHealthWithoutAura = "AverageHealthWithoutAura"

    public var isHealingAbsorbKind: Bool {
        switch self {
        case .unitsAboveHealingAbsorb, .unitsWithoutAuraAboveHealingAbsorb, .unitsWithAuraAboveHealingAbsorb: return true
        default: return false
        }
    }

    public var isAverageHealthKind: Bool {
        switch self {
        case .averageHealth, .averageHealthWithAura, .averageHealthWithoutAura: return true
        default: return false
        }
    }

    public var requiresAura: Bool {
        switch self {
        case .unitsBelowHealth, .unitsAboveHealingAbsorb, .averageHealth: return false
        default: return true
        }
    }
}

/// 模块内定义的命名动态单位。
public struct ModuleUnit: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var name = ""
    /// 非空时把该单位解析出槽位的 生命值 暴露成一个同名数值条件字段。
    public var healthName: String?
    public var kind: UnitSelectorKind = .lowestHealth
    public var healthThreshold: Int?
    public var healthThresholdField: String?
    public var roleFilter: UnitRoleFilterKind?
    public var role: Int?
    public var reverse = false
    public var auraSpellIds: [Int64]?
    /// 仅用于读取并迁移旧模块。
    public var auraNames: [String]?
    public var auraCount: Int?
    public var dispelType: Int?

    public init() {}

    public static func == (lhs: ModuleUnit, rhs: ModuleUnit) -> Bool {
        lhs.name == rhs.name && lhs.healthName == rhs.healthName && lhs.kind == rhs.kind
            && lhs.healthThreshold == rhs.healthThreshold && lhs.healthThresholdField == rhs.healthThresholdField
            && lhs.roleFilter == rhs.roleFilter && lhs.role == rhs.role && lhs.reverse == rhs.reverse
            && lhs.auraSpellIds == rhs.auraSpellIds && lhs.auraNames == rhs.auraNames
            && lhs.auraCount == rhs.auraCount && lhs.dispelType == rhs.dispelType
    }
}

/// 模块内定义的命名数量字段，仅用于条件。
public struct ModuleCountField: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var name = ""
    public var kind: CountKind = .unitsBelowHealth
    public var healthThreshold: Int?
    public var healthThresholdField: String?
    public var auraSpellId: Int64?
    public var auraName: String?
    /// 仅平均血量类使用。
    public var roleFilter: UnitRoleFilterKind?
    public var role: Int?

    public init() {}

    public static func == (lhs: ModuleCountField, rhs: ModuleCountField) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind && lhs.healthThreshold == rhs.healthThreshold
            && lhs.healthThresholdField == rhs.healthThresholdField && lhs.auraSpellId == rhs.auraSpellId && lhs.auraName == rhs.auraName
            && lhs.roleFilter == rhs.roleFilter && lhs.role == rhs.role
    }
}

public struct ModuleMatch: Sendable, Equatable {
    public var classId: Int?
    public var specId: Int?
    public var partyType: String?
    public var heroTalent: Int?

    public init(classId: Int? = nil, specId: Int? = nil, partyType: String? = nil, heroTalent: Int? = nil) {
        self.classId = classId
        self.specId = specId
        self.partyType = partyType
        self.heroTalent = heroTalent
    }

    public var specificity: Int {
        (classId == nil ? 0 : 1) + (specId == nil ? 0 : 1) + (Self.normalizePartyType(partyType) == nil ? 0 : 1) + (heroTalent == nil ? 0 : 1)
    }

    public func matches(classId: Int?, specId: Int?, partyType: Int?, heroTalent: Int?) -> Bool {
        Self.matchesOne(self.classId, classId)
            && Self.matchesOne(self.specId, specId)
            && Self.matchesPartyType(self.partyType, partyType)
            && Self.matchesOne(self.heroTalent, heroTalent)
    }

    /// 单人→0、团队→1-40、队伍→46、1..40→1-40、a-b 区间归一、其它文本原样。
    public static func normalizePartyType(_ value: String?) -> String? {
        guard let raw = value?.trimmed(), !raw.isEmpty, raw != "*", !raw.equalsIgnoringCase("any") else { return nil }
        if raw == "单人" { return "0" }
        if raw == "团队" { return "1-40" }
        if raw == "队伍" { return "46" }
        if let number = InvariantNumber.parseInt(raw) {
            return (1...40).contains(number) ? "1-40" : String(number)
        }
        let parts = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let start = InvariantNumber.parseInt(parts[0]), let end = InvariantNumber.parseInt(parts[1]) {
            return start <= end ? "\(start)-\(end)" : "\(end)-\(start)"
        }
        return raw
    }

    static func matchesOne(_ expected: Int?, _ actual: Int?) -> Bool {
        expected == nil || actual == expected
    }

    static func matchesPartyType(_ expected: String?, _ actual: Int?) -> Bool {
        guard let normalized = normalizePartyType(expected) else { return true }
        guard let actual else { return false }
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let start = InvariantNumber.parseInt(parts[0]), let end = InvariantNumber.parseInt(parts[1]) {
            return actual >= start && actual <= end
        }
        guard let exact = InvariantNumber.parseInt(normalized) else { return false }
        return actual == exact
    }

    public static func partyTypeSortKey(_ value: String?) -> Int {
        switch normalizePartyType(value) {
        case nil: return Int.max
        case "0": return 0
        case "1-40": return 1
        case "46": return 46
        case let other?:
            if let n = InvariantNumber.parseInt(other) { return n }
            return Int.max - 1
        }
    }
}

public struct ModuleRule: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var condition = ""
    public var comment = ""
    /// 此规则命中后，两次实际发送之间的最小间隔（毫秒）；nil/0 表示不限制。
    public var delayMs: Int?
    /// 此规则实际发送按键后，暂停整个逻辑循环的时长（毫秒）。
    public var logicDelayMs: Int?
    /// 命中并发送后是否继续判断后续规则。
    public var continueLogic: Bool?
    public var unit: Int?
    public var unitName: String?
    public var spell = ""
    /// nil 表示升级前的旧模块（运行时沿用原二元匹配）；空字符串表示明确选择无宏条件。
    public var macroCondition: String?
    public var hotkey = ""
    public var step = ""
    /// 子条件：与主条件是「且」关系，子条件之间是「或」关系。
    public var subConditions: [String]?

    public init() {}

    public static func == (lhs: ModuleRule, rhs: ModuleRule) -> Bool {
        lhs.enabled == rhs.enabled && lhs.condition == rhs.condition && lhs.comment == rhs.comment
            && lhs.delayMs == rhs.delayMs && lhs.logicDelayMs == rhs.logicDelayMs && lhs.continueLogic == rhs.continueLogic
            && lhs.unit == rhs.unit && lhs.unitName == rhs.unitName && lhs.spell == rhs.spell
            && lhs.macroCondition == rhs.macroCondition && lhs.hotkey == rhs.hotkey && lhs.step == rhs.step
            && lhs.subConditions == rhs.subConditions
    }

    public func describeCondition() -> String {
        guard let subs = subConditions, !subs.isEmpty else { return condition }
        let any = subs.joined(separator: " | ")
        return condition.isBlank ? "任一(\(any))" : "\(condition)  且任一(\(any))"
    }
}

public struct ModuleValueAdjustment: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var condition = ""
    public var field = ""
    public var delta = 0
    public var formula = ""

    public init() {}

    public static func == (lhs: ModuleValueAdjustment, rhs: ModuleValueAdjustment) -> Bool {
        lhs.enabled == rhs.enabled && lhs.condition == rhs.condition && lhs.field == rhs.field && lhs.delta == rhs.delta && lhs.formula == rhs.formula
    }
}

public struct ModuleDefinition: Sendable, Equatable, Identifiable {
    public static let currentUnitMappingVersion = 3

    public var id = ""
    public var name = "新模块"
    public var author = ""
    public var recommendedTalent = ""
    /// 保存时写入当时的 Shigure 版本。
    public var version = ""
    public var unitMappingVersion: Int?
    public var enabled = true
    public var match = ModuleMatch()
    public var units: [ModuleUnit] = []
    public var counts: [ModuleCountField] = []
    public var valueAdjustments: [ModuleValueAdjustment] = []
    public var rules: [ModuleRule] = []
    public var dependencies: ModuleDependencySnapshot?
    /// 运行时字段，不序列化。
    public var fileURL: URL?

    public init() {}

    public static func createDefault(name: String = "新模块") -> ModuleDefinition {
        var m = ModuleDefinition()
        m.id = ModuleStore.createModuleId(name)
        m.name = name
        m.version = AppInfo.version
        m.unitMappingVersion = currentUnitMappingVersion
        return m
    }

    public var hasCompatibleVersion: Bool {
        version.trimmed() == AppInfo.version.trimmed()
    }
}

/// 通用页「默认模块」条目。
public struct DefaultModuleSelection: Sendable, Equatable, Codable {
    public var classId: Int?
    public var specId: Int?
    public var heroTalent: Int?
    public var partyType: String?
    public var moduleId = ""

    public init(classId: Int? = nil, specId: Int? = nil, heroTalent: Int? = nil, partyType: String? = nil, moduleId: String = "") {
        self.classId = classId
        self.specId = specId
        self.heroTalent = heroTalent
        self.partyType = partyType
        self.moduleId = moduleId
    }

    public var specificity: Int {
        (classId == nil ? 0 : 1) + (specId == nil ? 0 : 1) + (heroTalent == nil ? 0 : 1) + (partyType == nil ? 0 : 1)
    }

    public func matches(classId: Int?, specId: Int?, partyType: Int?, heroTalent: Int?) -> Bool {
        ModuleMatch.matchesOne(self.classId, classId)
            && ModuleMatch.matchesOne(self.specId, specId)
            && ModuleMatch.matchesOne(self.heroTalent, heroTalent)
            && ModuleMatch(partyType: self.partyType).matches(classId: nil, specId: nil, partyType: partyType, heroTalent: nil)
    }

    public func hasSameFilter(classId: Int?, specId: Int?, partyType: String?, heroTalent: Int?) -> Bool {
        self.classId == classId && self.specId == specId && self.heroTalent == heroTalent
            && (ModuleMatch.normalizePartyType(self.partyType) ?? "").equalsIgnoringCase(ModuleMatch.normalizePartyType(partyType) ?? "")
    }
}
