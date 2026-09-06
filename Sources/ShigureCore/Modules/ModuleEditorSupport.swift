import Foundation

/// 模块编辑器用到的纯逻辑：字段目录合成、校验、旧引用迁移（对应 C# ModuleEditorControl 的非 UI 部分）。
public struct ModuleEditorSupport: Sendable {
    public let catalog: ConditionFieldCatalog

    public init(catalog: ConditionFieldCatalog) {
        self.catalog = catalog
    }

    // MARK: 字段目录

    /// 条件字段 = 状态/技能字段 + 规则设置伪字段 + 每个动态单位的裸名/值名称 + 数量 + 动态数值目标。
    public func conditionFields(module: ModuleDefinition, includeRuleSettings: Bool) -> [ConditionField] {
        var fields = catalog.fields(classId: module.match.classId, specId: module.match.specId)
        var seen = Set(fields.map(\.name))
        func add(_ f: ConditionField) { if seen.insert(f.name).inserted { fields.append(f) } }
        if includeRuleSettings {
            add(ConditionField(name: ShigureConditionFields.delay, displayName: "延迟 (ms)", type: .int, category: .shigure))
            add(ConditionField(name: ShigureConditionFields.logicDelay, displayName: "逻辑延迟 (ms)", type: .int, category: .shigure))
            add(ConditionField(name: ShigureConditionFields.continueLogic, displayName: "继续逻辑", type: .bool, category: .shigure))
        }
        for unit in module.units where !unit.name.isBlank {
            add(ConditionField(name: unit.name, displayName: "\(unit.name) (存在)", type: .bool, category: .dynamicUnit))
            if let health = unit.healthName, !health.isBlank {
                add(ConditionField(name: health, displayName: "\(health) (生命值)", type: .int, category: .dynamicUnit))
            }
        }
        for count in module.counts where !count.name.isBlank {
            add(ConditionField(name: count.name, displayName: "人数: \(count.name)", type: .int, category: .dynamicValue))
        }
        for name in adjustmentTargetFields(module: module) {
            add(ConditionField(name: name, displayName: "\(name) (动态数值)", type: .int, category: .dynamicValue))
        }
        return fields
    }

    /// 动态数值调整的目标字段：状态整数字段、物品冷却、技能/光环、单位生命值名、数量、公式目标。
    public func adjustmentFields(module: ModuleDefinition) -> [ConditionField] {
        var fields: [ConditionField] = []
        var seen = Set<String>()
        func add(_ name: String, _ display: String, _ category: ConditionFieldCategory) {
            if seen.insert(name).inserted { fields.append(ConditionField(name: name, displayName: display, type: .int, category: category)) }
        }
        for field in catalog.fields(classId: module.match.classId, specId: module.match.specId) {
            if field.category == .state && field.type == .int {
                add(field.name, field.displayName, .state)
            } else if field.category == .spell && field.classification == CooldownConditionClassifications.item && field.type == .int {
                add(field.name, field.displayName, .state)
            } else if field.category == .spell || field.category == .aura {
                add(field.name, field.displayName, field.category)
            }
        }
        for unit in module.units { if let h = unit.healthName, !h.isBlank { add(h, "\(h) (生命值)", .dynamicUnit) } }
        for count in module.counts where !count.name.isBlank { add(count.name, "人数: \(count.name)", .dynamicValue) }
        for name in adjustmentTargetFields(module: module) { add(name, "\(name) (动态数值)", .dynamicValue) }
        return fields
    }

    /// 阈值字段：状态/动态单位/动态数值类的可加减字段。
    public func thresholdFields(module: ModuleDefinition) -> [String] {
        adjustmentFields(module: module).filter { [.state, .dynamicUnit, .dynamicValue].contains($0.category) }.map(\.name)
    }

    /// 已有调整目标中不属于状态/技能/光环/单位/数量的名称 → 动态数值。
    public func adjustmentTargetFields(module: ModuleDefinition) -> [String] {
        let known = Set(catalog.fields(classId: module.match.classId, specId: module.match.specId).map(\.name))
        var exclude = known
        for unit in module.units { exclude.insert(unit.name); if let h = unit.healthName { exclude.insert(h) } }
        for count in module.counts { exclude.insert(count.name) }
        var result: [String] = []
        var seen = Set<String>()
        for adjustment in module.valueAdjustments {
            let name = adjustment.field.trimmed()
            if name.isEmpty || name.hasPrefixIgnoringCase("auras.") || name.hasPrefixIgnoringCase("spells.") || exclude.contains(name) { continue }
            if seen.insert(name).inserted { result.append(name) }
        }
        return result
    }

    /// 名称查重集合：其它单位/数量（含生命值名）+ 当前职业/专精的状态字段与 group 字段。
    public func takenNames(module: ModuleDefinition, excluding own: [String?]) -> Set<String> {
        var taken = Set<String>()
        for unit in module.units { taken.insert(unit.name.lowercased()); if let h = unit.healthName { taken.insert(h.lowercased()) } }
        for count in module.counts { taken.insert(count.name.lowercased()) }
        for f in catalog.fields(classId: module.match.classId, specId: module.match.specId) { taken.insert(f.name.lowercased()) }
        for f in catalog.groupFields(classId: module.match.classId, specId: module.match.specId) { taken.insert(f.name.lowercased()) }
        for name in own { if let name, !name.isEmpty { taken.remove(name.lowercased()) } }
        return taken
    }

    /// 动态单位/数量名称校验。
    public func validateName(_ name: String, taken: Set<String>) -> String? {
        if name.isEmpty { return "名称不能为空。" }
        if name.contains(".") || name.contains("$") { return "名称不能包含 '.' 或 '$'。" }
        if InvariantNumber.parseInt(name) != nil { return "名称不能是纯数字(会与单位编号混淆)。" }
        if taken.contains(name.lowercased()) { return "名称「\(name)」已被其它单位/字段或状态字段占用。" }
        return nil
    }

    // MARK: 校验（红行）

    public struct ValidationCatalog: Sendable {
        public let availableFields: Set<String>
        public let groupFields: Set<String>
        public let spellIds: Set<Int64>
        public let itemIds: Set<Int64>
        public let groupAuraIds: Set<Int64>
    }

    public func validationCatalog(module: ModuleDefinition) -> ValidationCatalog {
        let classId = module.match.classId
        let specId = module.match.specId
        var available = Set(conditionFields(module: module, includeRuleSettings: true).map { Self.normalizeFieldName($0.name) })
        var group = Set(catalog.groupFields(classId: classId, specId: specId).map(\.name))
        available.formUnion(catalog.auraAliasFieldNames(classId: classId, specId: specId, groupOnly: false))
        group.formUnion(catalog.auraAliasFieldNames(classId: classId, specId: specId, groupOnly: true))
        for unit in module.units where !unit.name.isBlank {
            for g in group { available.insert("\(unit.name).\(g)") }
        }
        let auraIds = Set(catalog.groupAuraFields(classId: classId, specId: specId).flatMap { field in
            field.name.split(separator: ".").compactMap { Int64($0) }
        })
        return ValidationCatalog(availableFields: available,
                                 groupFields: group,
                                 spellIds: Set(catalog.conditionSpells(classId: classId).map(\.spellId)),
                                 itemIds: Set(catalog.conditionItems(classId: classId).map(\.itemId)),
                                 groupAuraIds: auraIds)
    }

    /// 运行时允许 state./spell./aura. 别名且前缀不区分大小写；校验时归一化。
    public static func normalizeFieldName(_ fieldName: String) -> String {
        let name = fieldName.trimmed()
        if let rest = name.dropPrefixIgnoringCase("state.") { return rest }
        if let rest = name.dropPrefixIgnoringCase("spells.") { return "spells.\(rest)" }
        if let rest = name.dropPrefixIgnoringCase("spell.") { return "spells.\(rest)" }
        if let rest = name.dropPrefixIgnoringCase("auras.") { return "auras.\(rest)" }
        if let rest = name.dropPrefixIgnoringCase("aura.") { return "auras.\(rest)" }
        return name
    }

    /// 规则（主条件 + 子条件）里不存在的字段 / spellId / itemId。
    public func ruleIssues(_ rule: ModuleRule, catalog v: ValidationCatalog) -> [String] {
        var issues: [String] = []
        var seen = Set<String>()
        for expression in [rule.condition] + (rule.subConditions ?? []) {
            for term in ConditionExpression.parse(expression) {
                let original = term.field.trimmed()
                let normalized = Self.normalizeFieldName(original)
                if normalized.isEmpty { continue }
                var ok = v.availableFields.contains(normalized)
                if !ok {
                    let parts = normalized.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false)
                    if parts.count == 3, parts[0].lowercased() == "group", v.groupFields.contains(String(parts[2])) { ok = true }
                }
                if !ok, seen.insert("field:\(original)").inserted { issues.append("条件字段不存在：\(original)") }
                if SpellIdConditionFields.contains(term.field) {
                    let value = term.value.trimmed()
                    if !(Int64(value).map { $0 > 0 && v.spellIds.contains($0) } ?? false), seen.insert("spell:\(value)").inserted {
                        issues.append("\(term.field)不存在 spellId 为 \(value) 的法术")
                    }
                }
                if ItemIdConditionFields.contains(term.field) {
                    let value = term.value.trimmed()
                    if !(Int64(value).map { $0 > 0 && v.itemIds.contains($0) } ?? false), seen.insert("item:\(value)").inserted {
                        issues.append("\(term.field)不存在 itemId 为 \(value) 的物品")
                    }
                }
            }
        }
        return issues
    }

    public func unitIssues(_ unit: ModuleUnit, catalog v: ValidationCatalog) -> [String] {
        if let names = unit.auraNames, !names.isEmpty { return ["旧名称光环引用尚未转换：\(names.joined(separator: "、"))"] }
        let missing = (unit.auraSpellIds ?? []).filter { !v.groupAuraIds.contains($0) }
        return missing.isEmpty ? [] : ["队伍不存在 spellId 为 \(missing.map(String.init).joined(separator: "、")) 的光环"]
    }

    public func countIssues(_ count: ModuleCountField, catalog v: ValidationCatalog) -> [String] {
        if let name = count.auraName, !name.isBlank { return ["旧名称光环引用尚未转换：\(name)"] }
        if let id = count.auraSpellId, !v.groupAuraIds.contains(id) { return ["队伍不存在 spellId 为 \(id) 的光环"] }
        return []
    }

    public func adjustmentIssues(_ adjustment: ModuleValueAdjustment, module: ModuleDefinition, catalog v: ValidationCatalog) -> [String] {
        var issues: [String] = []
        let targets = Set(adjustmentFields(module: module).map { Self.normalizeFieldName($0.name) })
        let field = Self.normalizeFieldName(adjustment.field)
        if !field.isEmpty, !targets.contains(field), !v.availableFields.contains(field) {
            issues.append("调整目标不存在：\(adjustment.field)")
        }
        var pseudo = ModuleRule()
        pseudo.condition = adjustment.condition
        issues.append(contentsOf: ruleIssues(pseudo, catalog: v))
        if !adjustment.formula.isBlank {
            for name in Self.formulaIdentifiers(FormulaEvaluator.normalizeExpression(adjustment.formula)) {
                let normalized = Self.normalizeFieldName(name)
                if !v.availableFields.contains(normalized) && !targets.contains(normalized) {
                    issues.append("公式字段不存在：\(name)")
                }
            }
        }
        return issues
    }

    static func formulaIdentifiers(_ expression: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            let name = current.trimmed()
            current = ""
            guard !name.isEmpty, Double(name) == nil, !["int", "round", "floor", "ceil", "min", "max"].contains(name.lowercased()) else { return }
            if !result.contains(name) { result.append(name) }
        }
        for ch in expression {
            let scalar = ch.unicodeScalars.first!.value
            let isIdent = ch == "_" || ch == "$" || ch == "." || ch.isLetter || ch.isNumber || (scalar >= 0x3400 && scalar <= 0x9FFF)
            if isIdent { current.append(ch) } else { flush() }
        }
        flush()
        return result
    }

    // MARK: 旧引用迁移（名称 → spellId）

    /// 把旧模块中按名称保存的 auras.X / spells.X 引用改写成 spellId 键；无法唯一转换时返回错误。
    public func upgradeLegacySpellReferences(_ module: inout ModuleDefinition) -> String? {
        var candidates: [String: Set<String>] = [:]
        func add(_ legacy: String, _ current: String) {
            guard !legacy.isBlank, !current.isBlank else { return }
            candidates[legacy, default: []].insert(current)
        }
        if let spec = module.dependencies?.config.spec {
            func addAuras(_ entries: [ModuleAuraSnapshot], _ scope: String, _ prefix: String) {
                for aura in entries {
                    guard let id = SpellFieldKey.canonicalAuraId(spellId: aura.spellId, spellIds: aura.spellIds), !aura.name.isBlank else { continue }
                    add("auras.\(prefix)\(aura.name)", SpellFieldKey.aura(scope: scope, spellId: id))
                    if aura.maxApps != nil { add("auras.\(prefix)\(aura.name)层数", SpellFieldKey.aura(scope: scope, spellId: id, metric: SpellFieldKey.auraApplications)) }
                }
            }
            addAuras(spec.playerAuras, "player", "")
            addAuras(spec.targetHarmfulAuras, "target.harmful", "目标")
            addAuras(spec.targetHelpfulAuras, "target.helpful", "目标")
            addAuras(spec.focusHarmfulAuras, "focus.harmful", "焦点")
            addAuras(spec.focusHelpfulAuras, "focus.helpful", "焦点")
            for spell in spec.spells where spell.spellId > 0 && !spell.name.isBlank {
                add("spells.\(spell.name)", SpellFieldKey.spell(spellId: spell.spellId))
                if spell.charge { add("spells.\(spell.name)充能", SpellFieldKey.spell(spellId: spell.spellId, metric: SpellFieldKey.spellChargeCooldown)) }
                if spell.maxCharge != nil || spell.castCount != nil { add("spells.\(spell.name)层数", SpellFieldKey.spell(spellId: spell.spellId, metric: SpellFieldKey.spellCount)) }
            }
        }
        for field in catalog.groupFields(classId: module.match.classId, specId: module.match.specId) where field.name.hasPrefix("auras.") {
            let display = field.displayName.components(separatedBy: " / ").first?.trimmed() ?? field.displayName
            add(display, field.name)
        }
        let ambiguous = Set(candidates.filter { $0.value.count != 1 }.keys)
        let replacements = candidates.filter { $0.value.count == 1 }.mapValues { $0.first! }
        let dynamicNames = Array(Set((module.units.flatMap { [$0.name, $0.healthName ?? ""] } + module.counts.map(\.name)).map { $0.trimmed() }.filter { !$0.isEmpty }))

        enum ReplaceOutcome { case success(String), failure(String) }
        func replace(_ source: String, _ location: String) -> ReplaceOutcome {
            var result = source
            for name in dynamicNames {
                for (key, value) in replacements where name.contains(key) {
                    let corrupted = name.replacingOccurrences(of: key, with: value)
                    if corrupted != name { result = Self.replaceFieldReference(result, corrupted, name) }
                }
            }
            var protectedRefs: [(String, String)] = []
            for (index, name) in dynamicNames.enumerated() where Self.containsFieldReference(result, name) {
                let placeholder = "__SHIGURE_DYNAMIC_FIELD_\(index)__"
                result = Self.replaceFieldReference(result, name, placeholder)
                protectedRefs.append((placeholder, name))
            }
            for key in ambiguous where Self.containsFieldReference(result, key) {
                return .failure("\(location)：旧模块字段“\(key)”对应多个 spellId，请重新选择后再保存。")
            }
            for (key, value) in replacements.sorted(by: { $0.key.count > $1.key.count }) {
                result = Self.replaceFieldReference(result, key, value)
            }
            if let unresolved = Self.firstUnresolvedReference(result) {
                return .failure("\(location)：旧模块字段“\(unresolved)”无法转换为 spellId，请重新选择后再保存。")
            }
            for (placeholder, name) in protectedRefs { result = result.replacingOccurrences(of: placeholder, with: name) }
            return .success(result)
        }

        for index in module.rules.indices {
            let label = "规则第 \(index + 1) 行"
            switch replace(module.rules[index].condition, "\(label)主条件") {
            case .failure(let e): return e
            case .success(let text): module.rules[index].condition = text
            }
            if let subs = module.rules[index].subConditions {
                var updated: [String] = []
                for (i, sub) in subs.enumerated() {
                    switch replace(sub, "\(label)子条件第 \(i + 1) 行") {
                    case .failure(let e): return e
                    case .success(let text): updated.append(text)
                    }
                }
                module.rules[index].subConditions = updated
            }
        }
        for index in module.valueAdjustments.indices {
            let label = "动态数值第 \(index + 1) 行"
            for (keyPath, name) in [(\ModuleValueAdjustment.condition, "条件"), (\.field, "调整目标"), (\.formula, "公式")] as [(WritableKeyPath<ModuleValueAdjustment, String>, String)] {
                switch replace(module.valueAdjustments[index][keyPath: keyPath], "\(label)\(name)") {
                case .failure(let e): return e
                case .success(let text): module.valueAdjustments[index][keyPath: keyPath] = text
                }
            }
        }
        for index in module.units.indices {
            guard let names = module.units[index].auraNames, !names.isEmpty else { continue }
            var ids: [Int64] = []
            for name in names {
                guard let key = replacements[name], let id = Self.extractId(key) else {
                    return "动态单位第 \(index + 1) 行“\(module.units[index].name)”引用的队伍光环“\(name)”无法唯一转换为本地 spellId。"
                }
                if !ids.contains(id) { ids.append(id) }
            }
            module.units[index].auraSpellIds = ids
            module.units[index].auraNames = nil
        }
        for index in module.counts.indices {
            guard let name = module.counts[index].auraName, !name.isBlank else { continue }
            guard let key = replacements[name], let id = Self.extractId(key) else {
                return "动态数量第 \(index + 1) 行“\(module.counts[index].name)”引用的队伍光环“\(name)”无法唯一转换为本地 spellId。"
            }
            module.counts[index].auraSpellId = id
            module.counts[index].auraName = nil
        }
        return nil
    }

    private static let unresolvedRegex = try! NSRegularExpression(pattern: #"\b(?:auras|spells)\.[^\s&|<>=!+\-*/()]+"#)

    static func firstUnresolvedReference(_ text: String) -> String? {
        guard let match = unresolvedRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(match.range, in: text) else { return nil }
        let unresolved = String(text[r])
        if SpellFieldKey.parseAura(unresolved) != nil || SpellFieldKey.parseAuraMember(unresolved) != nil || SpellFieldKey.parseSpell(unresolved) != nil { return nil }
        return unresolved
    }

    static func fieldReferenceRegex(_ field: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: "(?<![_$\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: field) + "(?![_$\\p{L}\\p{N}])")
    }

    static func containsFieldReference(_ source: String, _ field: String) -> Bool {
        fieldReferenceRegex(field).firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil
    }

    static func replaceFieldReference(_ source: String, _ field: String, _ replacement: String) -> String {
        fieldReferenceRegex(field).stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    static func extractId(_ key: String) -> Int64? {
        key.split(separator: ".").compactMap { Int64($0) }.first { $0 > 0 }
    }

    // MARK: 显示

    /// 把条件表达式里的 spellId 键换成可读名（规则表显示用）。
    public func humanize(_ expression: String, spellName: (Int64) -> String?, itemName: (Int64) -> String?) -> String {
        let terms = ConditionExpression.parse(expression)
        guard !terms.isEmpty else { return expression }
        var out = ""
        for (i, term) in terms.enumerated() {
            var field = term.field
            if let spell = SpellFieldKey.parseSpell(field) {
                let metric = spell.metric == SpellFieldKey.spellChargeCooldown ? "充能" : (spell.metric == SpellFieldKey.spellCount ? "层数" : "cd")
                field = "\(metric):\(spellName(spell.spellId) ?? String(spell.spellId))"
            } else if let aura = SpellFieldKey.parseAura(field) {
                let metric = aura.metric == SpellFieldKey.auraApplications ? "层数" : "aura"
                field = "\(metric):\(spellName(aura.spellId) ?? String(aura.spellId))"
            }
            var value = term.value
            if SpellIdConditionFields.contains(term.field), let id = Int64(value.trimmed()), let name = spellName(id) { value = name }
            if ItemIdConditionFields.contains(term.field), let id = Int64(value.trimmed()), let name = itemName(id) { value = name }
            if term.field == "首领战", let n = Int(value.trimmed()) { value = n == 0 ? "非首领战" : (ReferenceData.bossName(number: n) ?? value) }
            let text = (term.op == "in" || term.op == "not in") ? "\(field) \(term.op) (\(value))" : "\(field) \(term.op) \(value)"
            if i > 0 { out += term.orWithPrevious ? " || " : " && " }
            out += text
        }
        return out
    }
}
