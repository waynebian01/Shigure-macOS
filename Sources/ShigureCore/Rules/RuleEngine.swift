import Foundation

public struct LogicDecision: Sendable, Equatable {
    public var hotkey: String?
    public var step: String
    public var unitInfo: [String: StateValue]
    public var moduleName: String?
    public var delayMs: Int
    public var rateLimitKey: String?
    public var logicDelayMs: Int

    public init(hotkey: String?, step: String, unitInfo: [String: StateValue], moduleName: String? = nil,
                delayMs: Int = 0, rateLimitKey: String? = nil, logicDelayMs: Int = 0) {
        self.hotkey = hotkey
        self.step = step
        self.unitInfo = unitInfo
        self.moduleName = moduleName
        self.delayMs = delayMs
        self.rateLimitKey = rateLimitKey
        self.logicDelayMs = logicDelayMs
    }
}

public struct LogicEvaluation: Sendable, Equatable {
    public let moduleName: String?
    public let decisions: [LogicDecision]
    /// 最后一个决策驱动界面显示。
    public var decision: LogicDecision? { decisions.last }

    public init(moduleName: String?, decisions: [LogicDecision]) {
        self.moduleName = moduleName
        self.decisions = decisions
    }
}

/// 模块规则执行（对应 C# ModuleLogic）。
public enum RuleEngine {
    public static func run(module: ModuleDefinition, state: inout GameState, keymap: any KeymapResolver) -> [LogicDecision] {
        var info = createInfo(module, state)
        let spellIndices = keymap.currentSpellIndices
        let itemIndices = keymap.currentItemIndices
        let unitSlots = resolveDynamicFields(module: module, state: &state, spellIndices: spellIndices, itemIndices: itemIndices)
        let failedSpells = keymap.currentFailedSpells
        let oneKeySpells = keymap.currentOneKeySpells
        let insertItems = keymap.currentInsertItems
        let spellNames = keymap.currentSpellNames
        let itemNames = keymap.currentItemNames
        let context = ConditionEvaluator.Context(failedSpells: failedSpells, spellIndices: spellIndices, itemIndices: itemIndices, insertItems: insertItems)
        var decisions: [LogicDecision] = []

        for (ruleIndex, rule) in module.rules.enumerated() {
            let rateLimitKey = "\(module.id):\(ruleIndex)"
            if !rule.enabled { continue }

            switch ConditionEvaluator.evaluateRule(rule, state: state, context: context) {
            case .error(let error):
                info["条件错误"] = .string(error)
                info["规则条件"] = .string(rule.describeCondition())
                addRuleLogInfo(&info, rule, ruleIndex, rateLimitKey, nil)
                return [LogicDecision(hotkey: nil, step: "\(module.name): 条件错误", unitInfo: info, moduleName: module.name)]
            case .matched(false):
                continue
            case .matched(true):
                break
            }

            if ModuleSpecialActions.isPauseSpell(rule.spell) {
                let desc = rule.describeCondition()
                info["命中条件"] = .string(desc.isBlank ? "始终" : desc)
                info["动作技能"] = .string(ModuleSpecialActions.pauseSpell)
                info["动作按键"] = .string("-")
                info["动作单位"] = .string("-")
                addRuleLogInfo(&info, rule, ruleIndex, rateLimitKey, nil)
                decisions.append(LogicDecision(hotkey: nil, step: "\(module.name): 暂停", unitInfo: info, moduleName: module.name))
                return decisions
            }

            var resolvedUnit = rule.unit
            if let unitName = rule.unitName, !unitName.isBlank {
                // 动态目标：选择器没选中任何单位时跳过该规则。
                guard let slot = unitSlots[unitName] ?? nil else { continue }
                resolvedUnit = Int(slot) ?? 0
            }

            var actionSpellId: Int64?
            var actionSpellName = rule.spell.trimmed()
            var isOneKeySpell = false
            var isFailedItem = false
            if ModuleSpecialActions.isFailedSpell(rule.spell) {
                guard let id = ModuleSpecialActions.failedSpell(in: state, map: failedSpells), let name = spellNames[id] else { continue }
                actionSpellId = id
                actionSpellName = name
            } else if ModuleSpecialActions.isFailedItem(rule.spell) {
                isFailedItem = true
                guard let id = ModuleSpecialActions.failedItem(in: state, map: insertItems), let name = itemNames[id] else { continue }
                actionSpellId = id
                actionSpellName = name
            } else if ModuleSpecialActions.isOneKeySpell(rule.spell) {
                isOneKeySpell = true
                guard let id = ModuleSpecialActions.oneKeySpell(in: state, map: oneKeySpells), let name = spellNames[id] else { continue }
                actionSpellId = id
                actionSpellName = name
                resolvedUnit = 0
            } else if let legacyId = InvariantNumber.parseInt64(actionSpellName), legacyId > 0, let legacyName = spellNames[legacyId] {
                // 兼容曾以 spellId 保存的普通动作。
                actionSpellName = legacyName
            }

            var resolvedMacroCondition = rule.macroCondition
            var hotkey: String?
            if !rule.hotkey.isBlank {
                hotkey = rule.hotkey.trimmed()
            } else if let id = actionSpellId, !isFailedItem {
                hotkey = keymap.hotkey(unit: resolvedUnit, spellId: id, macroCondition: resolvedMacroCondition)
            } else {
                hotkey = keymap.hotkey(unit: resolvedUnit, spell: actionSpellName, macroCondition: resolvedMacroCondition)
            }
            if isOneKeySpell, rule.hotkey.isBlank, hotkey.isNilOrBlank, let id = actionSpellId {
                hotkey = keymap.hotkey(unit: ReservedUnit.none, spellId: id, macroCondition: MacroConditionText.noChanneling)
                if !hotkey.isNilOrBlank {
                    resolvedUnit = ReservedUnit.none
                    resolvedMacroCondition = MacroConditionText.noChanneling
                }
            }

            let step = buildStep(module, rule, hotkey, actionSpellName)
            info["命中条件"] = .string(rule.condition.isBlank ? "始终" : rule.condition)
            info["动作技能"] = .string(actionSpellName.isBlank ? "-" : (actionSpellId.map { "\(actionSpellName) / \($0)" } ?? actionSpellName))
            info["宏条件"] = .string(resolvedMacroCondition.isNilOrBlank ? "-" : MacroConditionText.displayText(resolvedMacroCondition))
            info["动作按键"] = .string(hotkey.isNilOrBlank ? "-" : hotkey!)
            if let unitName = rule.unitName, !unitName.isBlank {
                info["动作单位"] = .string("\(unitName) → \(resolvedUnit ?? 0)")
            } else {
                info["动作单位"] = .int(resolvedUnit ?? 0)
            }
            addRuleLogInfo(&info, rule, ruleIndex, rateLimitKey, hotkey)
            decisions.append(LogicDecision(hotkey: hotkey, step: step, unitInfo: info, moduleName: module.name,
                                           delayMs: rule.delayMs ?? 0, rateLimitKey: rateLimitKey, logicDelayMs: rule.logicDelayMs ?? 0))
            if rule.continueLogic != true { return decisions }
        }

        if !decisions.isEmpty { return decisions }
        info["命中条件"] = .string("-")
        return [LogicDecision(hotkey: nil, step: "\(module.name): 无匹配规则", unitInfo: info, moduleName: module.name)]
    }

    private static func addRuleLogInfo(_ info: inout [String: StateValue], _ rule: ModuleRule, _ ruleIndex: Int, _ rateLimitKey: String, _ hotkey: String?) {
        info["动作按键"] = .string(hotkey.isNilOrBlank ? "-" : hotkey!)
        info["动作延迟"] = .string((rule.delayMs ?? 0) > 0 ? "\(rule.delayMs!) ms" : "-")
        info["逻辑延迟"] = .string((rule.logicDelayMs ?? 0) > 0 ? "\(rule.logicDelayMs!) ms" : "-")
        info["继续逻辑"] = .string(rule.continueLogic == true ? "是" : "-")
        info["规则编号"] = .int(ruleIndex + 1)
        info["限流键"] = .string(rateLimitKey)
    }

    private static func createInfo(_ module: ModuleDefinition, _ state: GameState) -> [String: StateValue] {
        [
            "模块": .string(module.name),
            "职业": .string(module.match.classId.map(String.init) ?? "*"),
            "专精": .string(module.match.specId.map(String.init) ?? "*"),
            "队伍类型": .int(state.getInt("队伍类型")),
            "英雄天赋": .int(state.getInt("英雄天赋")),
            "规则数": .int(module.rules.count)
        ]
    }

    private static func buildStep(_ module: ModuleDefinition, _ rule: ModuleRule, _ hotkey: String?, _ actionSpell: String?) -> String {
        if !rule.step.isBlank { return "\(module.name): \(rule.step.trimmed())" }
        if !rule.spell.isBlank {
            let spell = actionSpell.isNilOrBlank ? rule.spell.trimmed() : actionSpell!.trimmed()
            return hotkey.isNilOrBlank ? "\(module.name): 未找到按键 \(spell)" : "\(module.name): 施放 \(spell)"
        }
        return hotkey.isNilOrBlank ? "\(module.name): 命中规则" : "\(module.name): 发送 \(hotkey!)"
    }

    // MARK: 动态字段

    /// 把模块定义的动态单位/数量各解析一次并写入当前帧 state。按 dynamicModuleId 记忆化。
    @discardableResult
    public static func resolveDynamicFields(module: ModuleDefinition, state: inout GameState, spellIndices: [Int64: Int]?, itemIndices: [Int64: Int]?) -> [String: String?] {
        if let id = state.dynamicModuleId, id.equalsIgnoringCase(module.id), let existing = state.dynamicUnits {
            return existing
        }
        let context = ConditionEvaluator.Context(spellIndices: spellIndices, itemIndices: itemIndices)
        let thresholdFields = dynamicThresholdFields(module)
        let early = applyValueAdjustments(module, &state, context) { isEarlyThresholdAdjustment($0, thresholdFields) }
        let unitSlots = resolveUnits(module, &state)
        resolveCounts(module, &state)
        _ = applyValueAdjustments(module, &state, context) { !early.contains($0.id) }
        state.dynamicModuleId = module.id
        return unitSlots
    }

    private static func resolveUnits(_ module: ModuleDefinition, _ state: inout GameState) -> [String: String?] {
        var unitSlots: [String: String?] = [:]
        var unitHealth: [String: StateValue?] = [:]
        for unit in module.units where !unit.name.isBlank {
            let slot = UnitSelector.resolve(unit, state: state)
            unitSlots[unit.name] = .some(slot)
            if let healthName = unit.healthName, !healthName.isBlank {
                if let slot, let member = state.group[slot], let value = member["生命值"] {
                    unitHealth[healthName] = .some(value)
                } else {
                    unitHealth[healthName] = .some(nil)
                }
            }
        }
        state.dynamicUnits = unitSlots
        state.dynamicUnitHealth = unitHealth
        return unitSlots
    }

    private static func resolveCounts(_ module: ModuleDefinition, _ state: inout GameState) {
        var counts: [String: Int] = [:]
        for count in module.counts where !count.name.isBlank {
            counts[count.name] = UnitSelector.resolve(count, state: state)
        }
        state.dynamicCounts = counts
    }

    private static func applyValueAdjustments(_ module: ModuleDefinition, _ state: inout GameState, _ context: ConditionEvaluator.Context,
                                              include: (ModuleValueAdjustment) -> Bool) -> Set<UUID> {
        var applied = Set<UUID>()
        for adjustment in module.valueAdjustments where adjustment.enabled {
            if adjustment.field.isBlank || (adjustment.delta == 0 && adjustment.formula.isBlank) { continue }
            if !include(adjustment) { continue }
            guard case .matched(true) = ConditionEvaluator.evaluate(adjustment.condition, state: state, context: context) else { continue }
            if applyValueAdjustment(&state, adjustment) { applied.insert(adjustment.id) }
        }
        return applied
    }

    private static func isEarlyThresholdAdjustment(_ adjustment: ModuleValueAdjustment, _ thresholdFields: Set<String>) -> Bool {
        let key = adjustment.field.trimmed()
        return !key.isEmpty && !key.contains(".") && !key.hasPrefix("$") && thresholdFields.contains(key)
    }

    private static func dynamicThresholdFields(_ module: ModuleDefinition) -> Set<String> {
        var fields = Set<String>()
        for unit in module.units { if let f = unit.healthThresholdField, !f.isBlank { fields.insert(f.trimmed()) } }
        for count in module.counts { if let f = count.healthThresholdField, !f.isBlank { fields.insert(f.trimmed()) } }
        return fields
    }

    private static func applyValueAdjustment(_ state: inout GameState, _ adjustment: ModuleValueAdjustment) -> Bool {
        if !adjustment.formula.isBlank {
            guard case .success(let value) = FormulaEvaluator.evaluateInt(adjustment.formula, state: state) else { return false }
            setDynamicValue(&state, adjustment.field, .int(value))
            return true
        }
        applyValueDelta(&state, adjustment.field, adjustment.delta)
        return true
    }

    private static func setDynamicValue(_ state: inout GameState, _ field: String, _ value: StateValue) {
        let key = field.trimmed()
        if key.isEmpty { return }
        if let rest = key.dropPrefixIgnoringCase("auras.") {
            state.setAura(rest, value)
            return
        }
        if let rest = key.dropPrefixIgnoringCase("spells.") {
            state.setSpell(rest, value)
            return
        }
        var values = state.dynamicValues ?? [:]
        values[key] = .some(value)
        state.dynamicValues = values
    }

    private static func applyValueDelta(_ state: inout GameState, _ field: String, _ delta: Int) {
        let key = field.trimmed()
        if key.isEmpty { return }
        if let rest = key.dropPrefixIgnoringCase("auras.") {
            state.setAura(rest, .int(addDelta(state.auras[rest] ?? nil, delta)))
            return
        }
        if let rest = key.dropPrefixIgnoringCase("spells.") {
            state.setSpell(rest, .int(addDelta(state.spells[rest] ?? nil, delta)))
            return
        }
        if var counts = state.dynamicCounts, let current = counts[key] {
            counts[key] = current + delta
            state.dynamicCounts = counts
            return
        }
        if var health = state.dynamicUnitHealth, let current = health[key] {
            health[key] = .some(.int(addDelta(current, delta)))
            state.dynamicUnitHealth = health
            return
        }
        state.setValue(key, .int(addDelta(state.values[key] ?? nil, delta)))
    }

    /// 缺失/不可解析的基值视为 0。
    private static func addDelta(_ value: StateValue?, _ delta: Int) -> Int {
        (value?.intValue ?? 0) + delta
    }
}

/// 模块选择 + 默认逻辑（对应 C# LogicRegistry / DefaultClassLogic）。
public struct LogicRegistry: Sendable {
    public let keymapService: KeymapService
    public let moduleStore: ModuleStore
    public let selectedModuleId: String?
    public let defaultModules: [DefaultModuleSelection]

    public init(keymapService: KeymapService, moduleStore: ModuleStore, selectedModuleId: String?, defaultModules: [DefaultModuleSelection]) {
        self.keymapService = keymapService
        self.moduleStore = moduleStore
        self.selectedModuleId = selectedModuleId.isNilOrBlank ? nil : selectedModuleId!.trimmed()
        self.defaultModules = defaultModules
    }

    public func evaluate(classId: Int?, specId: Int?, specName: String?, state: inout GameState, runLogic: Bool) -> LogicEvaluation {
        let keymap = keymapService.select(classId: classId, specId: specId)
        if let module = findModule(classId: classId, specId: specId, state: state) {
            RuleEngine.resolveDynamicFields(module: module, state: &state, spellIndices: keymap.currentSpellIndices, itemIndices: keymap.currentItemIndices)
            return LogicEvaluation(moduleName: module.name, decisions: runLogic ? RuleEngine.run(module: module, state: &state, keymap: keymap) : [])
        }
        if !runLogic { return LogicEvaluation(moduleName: nil, decisions: []) }
        return LogicEvaluation(moduleName: nil, decisions: [Self.defaultLogic(state: state, keymap: keymap)])
    }

    public func findModule(classId: Int?, specId: Int?, state: GameState) -> ModuleDefinition? {
        let partyType = state.getInt("队伍类型")
        let heroTalent = state.getInt("英雄天赋")
        let defaultModuleId = defaultModules.enumerated()
            .filter { $0.element.matches(classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent) }
            .sorted { a, b in
                if a.element.specificity != b.element.specificity { return a.element.specificity > b.element.specificity }
                return a.offset > b.offset
            }
            .map(\.element.moduleId)
            .first { !$0.isBlank }
        return moduleStore.findSelectedOrBestMatch(selectedModuleId: selectedModuleId ?? defaultModuleId,
                                                   classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent)
    }

    /// 无模块时：仅当 一键辅助 == 10 且 keymap 有 一键辅助 时发送。
    static func defaultLogic(state: GameState, keymap: any KeymapResolver) -> LogicDecision {
        if state.getInt("一键辅助") == 10, let hotkey = keymap.hotkey(unit: 0, spell: "一键辅助", macroCondition: nil), !hotkey.isBlank {
            return LogicDecision(hotkey: hotkey, step: "施放 一键辅助", unitInfo: [:])
        }
        return LogicDecision(hotkey: nil, step: "职业逻辑尚未迁移", unitInfo: [:])
    }
}
