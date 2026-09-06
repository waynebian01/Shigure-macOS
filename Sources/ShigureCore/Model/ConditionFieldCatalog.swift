import Foundation

public enum ConditionFieldType: Sendable, Equatable {
    case int, bool, string
}

public enum ConditionFieldCategory: String, Sendable, Equatable, CaseIterable {
    case state = "状态"
    case shigure = "Shigure"
    case aura = "光环"
    case spell = "冷却"
    case dynamicUnit = "动态单位"
    case dynamicValue = "动态数值"
}

public struct ConditionField: Sendable, Equatable, Identifiable, Hashable {
    public let name: String
    public let displayName: String
    public let type: ConditionFieldType
    public let category: ConditionFieldCategory
    public let classification: String?
    public let itemId: Int64?
    public let spellId: Int64?
    /// 不在目录中、由现有条件带入的自定义字段。
    public var isCustom = false

    public var id: String { name }

    public init(name: String, displayName: String, type: ConditionFieldType, category: ConditionFieldCategory = .state,
                classification: String? = nil, itemId: Int64? = nil, spellId: Int64? = nil, isCustom: Bool = false) {
        self.name = name
        self.displayName = displayName
        self.type = type
        self.category = category
        self.classification = classification
        self.itemId = itemId
        self.spellId = spellId
        self.isCustom = isCustom
    }

    public static func == (lhs: ConditionField, rhs: ConditionField) -> Bool { lhs.name == rhs.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

public struct ConditionSpell: Sendable, Identifiable, Hashable {
    public let spellId: Int64
    public let index: Int
    public let name: String
    public var id: Int64 { spellId }
    public var displayName: String { "\(name) / \(spellId)" }
}

public struct ConditionItem: Sendable, Identifiable, Hashable {
    public let itemId: Int64
    public let index: Int
    public let name: String
    public var id: Int64 { itemId }
    public var displayName: String { "\(name) / \(itemId)" }
}

public enum CooldownConditionClassifications {
    public static let spell = "技能"
    public static let item = "物品"
}

/// 从 config 目录构建条件编辑器可选择的字段目录（按职业/专精过滤）。
public struct ConditionFieldCatalog: Sendable {
    static let removedCastFields: Set<String> = ["施法", "目标施法", "焦点施法", "首领1施法", "首领2施法", "首领3施法", "首领4施法", "首领5施法"]
    static let nonAuraGroupFields: Set<String> = ["生命值", "职责", "驱散", "治疗吸收"]

    public let config: ConfigService?
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.init(paths: paths, config: try? ConfigService.load(configDirectory: paths.configDirectory))
    }

    /// Allows callers that build the catalog asynchronously to provide a preloaded config.
    /// Passing nil creates an empty catalog without touching the filesystem.
    public init(paths: AppPaths, config: ConfigService?) {
        self.paths = paths
        self.config = config
    }

    /// 指定职业/专精下可用的条件字段；classId/specId 为空时只返回公共字段。
    public func fields(classId: Int?, specId: Int?) -> [ConditionField] {
        guard let config else { return [] }
        var fields: [ConditionField] = []
        var seen = Set<String>()
        let stateConfig = config.buildStateConfig(classId: classId, specId: specId)
        let sourceClassifications = loadSourceClassifications(classId: classId, specId: specId)

        func add(_ field: ConditionField) {
            if seen.insert(field.name).inserted { fields.append(field) }
        }

        for (key, node) in stateConfig.entries {
            if key == "group" || key == "spells" || key == "auras" || key == "锚点" || Self.removedCastFields.contains(key) { continue }
            guard case .object(let field) = node, field.contains("step") else { continue }
            let classification = Self.readClassification(field) ?? sourceClassifications[key] ?? ClassStateCatalog.classifyField(key)
            let itemId = JSONHelpers.getLong(field["itemId"]).flatMap { $0 > 0 ? $0 : nil }
            if itemId != nil || classification == ClassStateCatalog.categoryItem {
                let display = Self.readDisplayName(field) ?? key
                add(ConditionField(name: key, displayName: itemId.map { "\(display) / \($0)" } ?? display, type: Self.readType(field),
                                   category: .spell, classification: CooldownConditionClassifications.item, itemId: itemId))
                continue
            }
            add(ConditionField(name: key, displayName: key, type: Self.readType(field), category: .state, classification: classification, itemId: itemId))
        }
        if let auras = stateConfig.object("auras") {
            for (auraName, node) in auras.entries {
                guard case .object(let field) = node, field.contains("step") else { continue }
                let display = Self.readDisplayName(field) ?? auraName
                let spellId = JSONHelpers.getLong(field["spellId"])
                add(ConditionField(name: "auras.\(auraName)", displayName: "\(display) / \(spellId.map(String.init) ?? "?")", type: Self.readType(field),
                                   category: .aura, classification: Self.readClassification(field) ?? sourceClassifications["auras.\(auraName)"] ?? Self.inferAuraClassification(auraName), spellId: spellId))
            }
        }
        if let spells = stateConfig.object("spells") {
            for (spellName, node) in spells.entries {
                guard case .object(let field) = node, field.contains("step") else { continue }
                let display = Self.readDisplayName(field) ?? spellName
                let spellId = JSONHelpers.getLong(field["spellId"])
                add(ConditionField(name: "spells.\(spellName)", displayName: "\(display) / \(spellId.map(String.init) ?? "?")", type: Self.readType(field),
                                   category: .spell, classification: CooldownConditionClassifications.spell, spellId: spellId))
            }
        }
        add(ConditionField(name: ModuleSpecialActions.failedSpell, displayName: ModuleSpecialActions.failedSpell, type: .string, category: .state, classification: ClassStateCatalog.categoryState))
        add(ConditionField(name: ModuleSpecialActions.failedItem, displayName: ModuleSpecialActions.failedItem, type: .string, category: .state, classification: ClassStateCatalog.categoryState))
        return fields
    }

    /// group 队伍成员字段（生命值/职责/驱散 + 该专精光环 + 治疗吸收）。
    public func groupFields(classId: Int?, specId: Int?) -> [ConditionField] {
        guard let config else { return [] }
        let stateConfig = config.buildStateConfig(classId: classId, specId: specId)
        guard let group = stateConfig.object("group") else { return [] }
        var fields: [ConditionField] = []
        var seen = Set<String>()
        for (key, node) in group.entries {
            if key == "start" || key == "num" { continue }
            guard case .object(let field) = node, field.contains("step"), seen.insert(key).inserted else { continue }
            let display = Self.readDisplayName(field) ?? key
            let spellId = JSONHelpers.getLong(field["spellId"])
            fields.append(ConditionField(name: key, displayName: spellId.map { "\(display) / \($0)" } ?? display, type: Self.readType(field), spellId: spellId))
        }
        if seen.insert("治疗吸收").inserted {
            fields.append(ConditionField(name: "治疗吸收", displayName: "治疗吸收", type: .int))
        }
        return fields
    }

    /// 队伍光环字段（排除 生命值/职责/驱散/治疗吸收）。
    public func groupAuraFields(classId: Int?, specId: Int?) -> [ConditionField] {
        groupFields(classId: classId, specId: specId).filter { !Self.nonAuraGroupFields.contains($0.name) }
    }

    /// 多 ID 光环除规范 ID 外仍可解析的字段名（不进下拉，仅用于校验）。
    public func auraAliasFieldNames(classId: Int?, specId: Int?, groupOnly: Bool) -> Set<String> {
        guard let config else { return [] }
        var aliases = Set<String>()
        let stateConfig = config.buildStateConfig(classId: classId, specId: specId)
        func add(_ fieldName: String, _ field: JSONObject, includeScope: Bool) {
            guard let canonical = JSONHelpers.getLong(field["spellId"]), let metric = JSONHelpers.getString(field["metric"]), !metric.isBlank,
                  let ids = field.array("spellIds") else { return }
            let scope = JSONHelpers.getString(field["scope"]) ?? ""
            for node in ids {
                guard let alias = JSONHelpers.getLong(node), alias > 0, alias != canonical else { continue }
                aliases.insert(includeScope ? "auras.\(scope).\(alias).\(metric)" : "auras.\(alias).\(metric)")
            }
        }
        if !groupOnly, let auras = stateConfig.object("auras") {
            for (name, node) in auras.entries { if case .object(let f) = node { add("auras.\(name)", f, includeScope: true) } }
        }
        if groupOnly, let group = stateConfig.object("group") {
            for (name, node) in group.entries where name.hasPrefix("auras.") { if case .object(let f) = node { add(name, f, includeScope: false) } }
        }
        return aliases
    }

    /// 当前职业 spellsList / itemsList（条件编辑器中 spellId/itemId 字段的值选项）。
    public func conditionSpells(classId: Int?) -> [ConditionSpell] {
        guard let classId, let doc = try? ClassBlocksStore.load(paths.classLuaFile(classId: classId)) else { return [] }
        return doc.spellsList.filter { $0.spellId > 0 }.sorted { ($0.index, $0.spellId) < ($1.index, $1.spellId) }
            .map { ConditionSpell(spellId: $0.spellId, index: $0.index, name: $0.name) }
    }

    public func conditionItems(classId: Int?) -> [ConditionItem] {
        guard let classId, let doc = try? ClassBlocksStore.load(paths.classLuaFile(classId: classId)) else { return [] }
        return doc.itemsList.filter { $0.itemId > 0 }.sorted { ($0.index, $0.itemId) < ($1.index, $1.itemId) }
            .map { ConditionItem(itemId: $0.itemId, index: $0.index, name: $0.name) }
    }

    private func loadSourceClassifications(classId: Int?, specId: Int?) -> [String: String] {
        var result: [String: String] = [:]
        guard let classId, let specId else { return result }
        guard let doc = try? ClassBlocksStore.load(paths.classLuaFile(classId: classId)), let spec = doc.specs[specId] else { return result }
        if spec.nestedStates {
            for (classification, names) in spec.categorizedStates {
                for source in names {
                    let name = source == "法术失败" ? ModuleSpecialActions.insertSpellState : source
                    let key = ClassStateCatalog.isUnitPrefixCategory(classification) ? classification + name : name
                    result[key] = classification
                }
            }
            for item in spec.items where !item.name.isBlank { result[item.name] = ClassStateCatalog.categoryItem }
        } else {
            for source in spec.flatStates {
                let name = source == "法术失败" ? ModuleSpecialActions.insertSpellState : source
                result[name] = ClassStateCatalog.classifyField(name)
            }
        }
        for aura in spec.playerAuras { result["auras.\(aura.name)"] = "玩家" }
        for aura in spec.targetHarmfulAuras { result["auras.目标\(aura.name)"] = "目标减益" }
        for aura in spec.targetHelpfulAuras { result["auras.目标\(aura.name)"] = "目标增益" }
        for aura in spec.focusHarmfulAuras { result["auras.焦点\(aura.name)"] = "焦点减益" }
        for aura in spec.focusHelpfulAuras { result["auras.焦点\(aura.name)"] = "焦点增益" }
        return result
    }

    static func readClassification(_ field: JSONObject) -> String? {
        guard let value = JSONHelpers.getString(field["category"])?.trimmed(), !value.isEmpty else { return nil }
        return value
    }

    static func readDisplayName(_ field: JSONObject) -> String? {
        guard let value = JSONHelpers.getString(field["displayName"])?.trimmed(), !value.isEmpty else { return nil }
        return value
    }

    static func inferAuraClassification(_ name: String) -> String {
        name.hasPrefix("目标") ? "目标光环" : (name.hasPrefix("焦点") ? "焦点光环" : "玩家")
    }

    static func readType(_ field: JSONObject) -> ConditionFieldType {
        switch JSONHelpers.getString(field["type"]) {
        case "bool": return .bool
        case "string": return .string
        default: return .int
        }
    }
}
