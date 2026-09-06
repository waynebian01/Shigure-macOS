import AppKit
import Observation
import ShigureCore

/// 模块编辑器状态（对应 C# ModuleEditorControl 的数据部分）。草稿为值类型，保存时才写盘。
@MainActor
@Observable
final class ModuleEditorStore {
    unowned let model: AppModel

    private(set) var modules: [ModuleDefinition] = []
    private(set) var selectedId: String?
    var draft = ModuleDefinition()
    private var original = ModuleDefinition()
    var selectedTab = 0
    var hasSelection = false
    var errorMessage: String?
    var infoMessage: String?
    var pendingDeleteName: String?

    private(set) var support: ModuleEditorSupport
    private(set) var keymapCatalog: KeymapEditorCatalog = .empty
    @ObservationIgnored private(set) var validation: ModuleEditorSupport.ValidationCatalog?
    @ObservationIgnored private var validationModuleKey = ""
    @ObservationIgnored private var rulePresentationCache: [UUID: RulePresentation] = [:]
    @ObservationIgnored private var rulePresentationKey = ""
    private var loadedCatalogVersion = -1
    private var loadedModuleVersion = -1
    private var loadedClassId: Int? = nil
    @ObservationIgnored private var catalogTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        // Catalog construction parses all class Lua/config files; defer it so the page can render first.
        support = ModuleEditorSupport(catalog: ConditionFieldCatalog(paths: model.paths, config: nil))
        reload()
    }

    deinit {
        catalogTask?.cancel()
    }

    var isDirty: Bool { hasSelection && draft != original }

    // MARK: 列表

    /// 离开页面期间配置也可能被其它编辑器更新。刷新目录时保留未保存草稿。
    func synchronize() {
        if loadedModuleVersion != model.moduleReloadVersion {
            if isDirty {
                modules = model.moduleStore.getModulesForDisplay()
                loadedModuleVersion = model.moduleReloadVersion
            } else {
                reload()
            }
        }
        if loadedCatalogVersion != model.catalogVersion { refreshCatalogs() }
    }

    func reload(reloadStore: Bool = false) {
        if reloadStore { model.moduleStore.reload() }
        modules = model.moduleStore.getModulesForDisplay()
        loadedModuleVersion = model.moduleReloadVersion
        if let selectedId, let module = modules.first(where: { $0.id == selectedId }) {
            load(module)
        } else if let first = modules.first {
            select(first.id)
        } else {
            hasSelection = false
            selectedId = nil
        }
    }

    func refreshCatalogs() {
        scheduleCatalogLoad()
    }

    func select(_ id: String) {
        guard selectedId != id || !hasSelection else { return }
        guard let module = modules.first(where: { $0.id == id }) else { return }
        selectedId = id
        load(module)
    }

    private func load(_ module: ModuleDefinition) {
        // 撤销栈里的规则快照属于上一个模块，切换后必须作废。
        undoManager?.removeAllActions(withTarget: self)
        draft = module
        original = module
        hasSelection = true
        scheduleCatalogLoad()
        invalidateValidation()
    }

    func hasImportIssue(_ module: ModuleDefinition) -> Bool {
        model.moduleStore.hasImportIssue(module.id) || !module.hasCompatibleVersion
    }

    private func scheduleCatalogLoad() {
        catalogTask?.cancel()
        let paths = model.paths
        let classId = draft.match.classId
        let moduleId = draft.id
        let catalogVersion = model.catalogVersion
        catalogTask = Task { [weak self] in
            // 在任务开始前检查是否需要重新加载
            guard let self else { return }
            let needsReload = self.loadedCatalogVersion != catalogVersion || self.loadedClassId != classId
            guard needsReload else { return }

            let result = await Task.detached(priority: .utility) {
                let config = try? ConfigService.load(configDirectory: paths.configDirectory)
                let catalog = ConditionFieldCatalog(paths: paths, config: config)
                let keymapName = config?.keymapName(classId: classId)
                let keymapURL = KeymapCatalog.resolveKeymapFile(keymapDirectory: paths.keymapDirectory, keymapName: keymapName)
                let keymap = KeymapEditorCatalog.load(keymapURL)
                let spells = catalog.conditionSpells(classId: classId)
                let items = catalog.conditionItems(classId: classId)
                return (catalog, keymap, spells, items)
            }.value
            guard !Task.isCancelled else { return }
            guard self.draft.id == moduleId else { return }
            self.support = ModuleEditorSupport(catalog: result.0)
            self.keymapCatalog = result.1
            self.loadedCatalogVersion = catalogVersion
            self.loadedClassId = classId
            for spell in result.2 { self.model.iconCatalog.register(spellId: spell.spellId, name: spell.name) }
            for item in result.3 { self.model.iconCatalog.registerItem(itemId: item.itemId, name: item.name) }
            self.invalidateValidation()
        }
    }

    // MARK: 匹配

    func setClass(_ classId: Int?) {
        draft.match.classId = classId
        if classId == nil || draft.match.specId.map({ s in !ClassNames.specs(of: classId!).contains { $0.id == s } }) ?? false { draft.match.specId = nil }
        draft.match.heroTalent = nil
        scheduleCatalogLoad()
        invalidateValidation()
        for i in draft.rules.indices { applySpellChange(ruleIndex: i, keepTarget: true) }
    }

    func setSpec(_ specId: Int?) {
        draft.match.specId = specId
        draft.match.heroTalent = nil
        scheduleCatalogLoad()
        invalidateValidation()
    }

    // MARK: 校验

    func invalidateValidation() {
        validation = nil
        validationModuleKey = ""
        rulePresentationCache.removeAll(keepingCapacity: true)
        rulePresentationKey = ""
    }

    var validationCatalog: ModuleEditorSupport.ValidationCatalog {
        let key = validationKeyForCurrentDraft
        if let validation, validationModuleKey == key { return validation }
        let v = support.validationCatalog(module: draft)
        validation = v
        validationModuleKey = key
        return v
    }

    func issues(for rule: ModuleRule) -> [String] { support.ruleIssues(rule, catalog: validationCatalog) }
    func issues(for unit: ModuleUnit) -> [String] { support.unitIssues(unit, catalog: validationCatalog) }
    func issues(for count: ModuleCountField) -> [String] { support.countIssues(count, catalog: validationCatalog) }
    func issues(for adjustment: ModuleValueAdjustment) -> [String] { support.adjustmentIssues(adjustment, module: draft, catalog: validationCatalog) }

    /// 规则行会同时显示校验结果和可读条件。按行缓存可以避免 SwiftUI 在列表布局、图标加载
    /// 和焦点变化时重复解析同一条规则。
    func rulePresentation(for rule: ModuleRule) -> RulePresentation {
        let key = rulePresentationKeyForCurrentDraft
        if key != rulePresentationKey {
            rulePresentationCache.removeAll(keepingCapacity: true)
            rulePresentationKey = key
        }
        if let cached = rulePresentationCache[rule.id], cached.rule == rule {
            return cached
        }

        let issues = support.ruleIssues(rule, catalog: validationCatalog)
        var text = support.humanize(rule.condition,
                                    spellName: { model.iconCatalog.spellName($0) },
                                    itemName: { model.iconCatalog.itemName($0) })
        if let subs = rule.subConditions, !subs.isEmpty {
            let any = subs.map {
                support.humanize($0,
                                 spellName: { model.iconCatalog.spellName($0) },
                                 itemName: { model.iconCatalog.itemName($0) })
            }.joined(separator: " | ")
            text = text.isBlank ? String(localized: "任一(\(any))") : String(localized: "\(text)  且任一(\(any))")
        }
        if text.isBlank { text = String(localized: "始终命中") }
        if let delay = rule.delayMs, delay > 0 { text += String(localized: "；延迟 \(delay) ms") }
        if let delay = rule.logicDelayMs, delay > 0 { text += String(localized: "；逻辑延迟 \(delay) ms") }
        if rule.continueLogic == true { text += String(localized: "；继续逻辑") }

        let result = RulePresentation(rule: rule, issues: issues, conditionDisplay: text)
        rulePresentationCache[rule.id] = result
        return result
    }

    private var rulePresentationKeyForCurrentDraft: String {
        "\(validationKeyForCurrentDraft)/catalog:\(loadedCatalogVersion)/icons:\(model.iconCatalog.version)"
    }

    private var validationKeyForCurrentDraft: String {
        "\(draft.match.classId ?? -1)/\(draft.match.specId ?? -1)/\(draft.units.map(\.name).joined(separator: ","))/\(draft.units.compactMap(\.healthName).joined(separator: ","))/\(draft.counts.map(\.name).joined(separator: ","))/\(draft.valueAdjustments.map(\.field).joined(separator: ","))"
    }

    struct RulePresentation {
        let rule: ModuleRule
        let issues: [String]
        let conditionDisplay: String
    }

    // MARK: 规则

    var spellOptions: [String] {
        var options = ModuleSpecialActions.all
        var seen = Set(options)
        for spell in keymapCatalog.spells where seen.insert(spell).inserted { options.append(spell) }
        for rule in draft.rules where !rule.spell.isBlank && seen.insert(rule.spell).inserted { options.append(rule.spell) }
        return options
    }

    /// 目标选项标签："" 无、"u:<n>" keymap 单位、"n:<name>" 动态单位。
    func targetOptions(for rule: ModuleRule) -> [(tag: String, label: String)] {
        var options: [(String, String)] = [("", "")]
        if ModuleSpecialActions.isPauseSpell(rule.spell) { return options }
        if ModuleSpecialActions.isOneKeySpell(rule.spell) { return [("u:0", ReservedUnit.displayText(0))] }
        for unit in allowedUnits(for: rule.spell) { options.append(("u:\(unit)", ReservedUnit.displayText(unit))) }
        for unit in draft.units where !unit.name.isBlank && !options.contains(where: { $0.0 == "n:\(unit.name)" }) {
            options.append(("n:\(unit.name)", unit.name))
        }
        let current = targetTag(rule)
        if !current.isEmpty, !options.contains(where: { $0.0 == current }) {
            options.append((current, targetLabel(rule)))
        }
        return options
    }

    private func allowedUnits(for spell: String) -> [Int] {
        let classId = draft.match.classId
        if ModuleSpecialActions.isFailedSpell(spell) {
            let ids = Set((support.catalog.config?.failedSpells(classId: classId) ?? [:]).values)
            let names = support.catalog.conditionSpells(classId: classId).filter { ids.contains($0.spellId) }.map(\.name)
            return keymapCatalog.units(forSpells: names)
        }
        if ModuleSpecialActions.isFailedItem(spell) {
            let ids = Set((support.catalog.config?.insertItems(classId: classId) ?? [:]).values)
            let names = support.catalog.conditionItems(classId: classId).filter { ids.contains($0.itemId) }.map(\.name)
            return keymapCatalog.units(forSpells: names)
        }
        return keymapCatalog.units(forSpell: spell)
    }

    func targetTag(_ rule: ModuleRule) -> String {
        if let name = rule.unitName, !name.isBlank { return "n:\(name)" }
        if let unit = rule.unit { return "u:\(unit)" }
        return ""
    }

    func targetLabel(_ rule: ModuleRule) -> String {
        if let name = rule.unitName, !name.isBlank { return name }
        if let unit = rule.unit { return ReservedUnit.displayText(unit) }
        return ""
    }

    func setTarget(ruleIndex: Int, tag: String) {
        guard draft.rules.indices.contains(ruleIndex) else { return }
        if tag.hasPrefix("n:") {
            draft.rules[ruleIndex].unitName = String(tag.dropFirst(2))
            draft.rules[ruleIndex].unit = nil
        } else if tag.hasPrefix("u:") {
            draft.rules[ruleIndex].unitName = nil
            draft.rules[ruleIndex].unit = Int(tag.dropFirst(2))
        } else {
            draft.rules[ruleIndex].unitName = nil
            draft.rules[ruleIndex].unit = nil
        }
        applyMacroConditionRules(ruleIndex: ruleIndex)
    }

    func macroConditionOptions(for rule: ModuleRule) -> [String] {
        var options = [""]
        let unit = rule.unitName.isNilOrBlank ? rule.unit : nil
        if let unit, !rule.spell.isBlank {
            for c in keymapCatalog.macroConditions(spell: rule.spell, unit: unit) {
                let display = MacroConditionText.displayText(c)
                if !options.contains(display) { options.append(display) }
            }
        }
        let current = MacroConditionText.displayText(rule.macroCondition)
        if !current.isEmpty, !options.contains(current) { options.append(current) }
        return options
    }

    /// 技能变化后按 C# RebuildUnitCell/RebuildMacroConditionCell 规则重建目标与宏条件。
    func applySpellChange(ruleIndex: Int, keepTarget: Bool = false) {
        guard draft.rules.indices.contains(ruleIndex) else { return }
        let rule = draft.rules[ruleIndex]
        let spell = rule.spell
        if ModuleSpecialActions.isPauseSpell(spell) {
            draft.rules[ruleIndex].unit = nil
            draft.rules[ruleIndex].unitName = nil
        } else if ModuleSpecialActions.isOneKeySpell(spell) {
            draft.rules[ruleIndex].unit = 0
            draft.rules[ruleIndex].unitName = nil
        } else {
            let allowed = allowedUnits(for: spell)
            let current = targetTag(rule)
            let dynamicNames = Set(draft.units.map { "n:\($0.name)" })
            let legal = current.isEmpty || dynamicNames.contains(current) || allowed.contains { "u:\($0)" == current }
            if !legal && !allowed.isEmpty && !keepTarget {
                draft.rules[ruleIndex].unit = nil
                draft.rules[ruleIndex].unitName = nil
            }
        }
        applyMacroConditionRules(ruleIndex: ruleIndex)
    }

    private func applyMacroConditionRules(ruleIndex: Int) {
        let rule = draft.rules[ruleIndex]
        let desired = MacroConditionText.displayText(rule.macroCondition)
        let unit = rule.unitName.isNilOrBlank ? rule.unit : nil
        let allowed: [String] = (unit != nil && !rule.spell.isBlank) ? keymapCatalog.macroConditions(spell: rule.spell, unit: unit) : []
        let displays = allowed.map { MacroConditionText.displayText($0) }
        if !desired.isEmpty, displays.contains(desired) { return }
        if !desired.isEmpty, allowed.isEmpty { return }
        let nonEmpty = displays.filter { !$0.isBlank }
        draft.rules[ruleIndex].macroCondition = (nonEmpty.count == 1 && allowed.count == 1) ? nonEmpty[0] : ""
    }

    func addRule() {
        mutateRules(String(localized: "添加规则")) {
            var rule = ModuleRule()
            rule.macroCondition = ""
            draft.rules.append(rule)
        }
    }

    func duplicateRule(at index: Int) {
        guard draft.rules.indices.contains(index) else { return }
        mutateRules(String(localized: "复制规则")) {
            var copy = draft.rules[index]
            copy.id = UUID()
            draft.rules.insert(copy, at: index + 1)
        }
    }

    func insertBlankRule(after index: Int) {
        mutateRules(String(localized: "添加规则")) {
            var rule = ModuleRule()
            rule.macroCondition = ""
            draft.rules.insert(rule, at: min(index + 1, draft.rules.count))
        }
    }

    func deleteRule(at index: Int) {
        guard draft.rules.indices.contains(index) else { return }
        mutateRules(String(localized: "删除规则")) { draft.rules.remove(at: index) }
    }

    func moveRule(from index: Int, by delta: Int) {
        let target = index + delta
        guard draft.rules.indices.contains(index), draft.rules.indices.contains(target) else { return }
        mutateRules(String(localized: "移动规则")) { draft.rules.swapAt(index, target) }
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        mutateRules(String(localized: "移动规则")) { draft.rules.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: 撤销

    /// 由规则页在出现时注入。只有增删复制移动这类结构性改动进撤销栈；
    /// 行内文本框自己有编辑撤销，重复登记反而会打断输入。
    var undoManager: UndoManager?

    private func mutateRules(_ actionName: String, _ body: () -> Void) {
        let before = draft.rules
        body()
        guard draft.rules != before else { return }
        registerRulesUndo(restoring: before, actionName: actionName)
    }

    private func registerRulesUndo(restoring snapshot: [ModuleRule], actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.draft.rules
                store.draft.rules = snapshot
                store.registerRulesUndo(restoring: current, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: 单位 / 数量 / 数值

    func upsertUnit(_ unit: ModuleUnit) {
        if let i = draft.units.firstIndex(where: { $0.id == unit.id }) { draft.units[i] = unit } else { draft.units.append(unit) }
        invalidateValidation()
    }

    func upsertCount(_ count: ModuleCountField) {
        if let i = draft.counts.firstIndex(where: { $0.id == count.id }) { draft.counts[i] = count } else { draft.counts.append(count) }
        invalidateValidation()
    }

    func deleteUnit(_ unit: ModuleUnit) {
        draft.units.removeAll { $0.id == unit.id }
        invalidateValidation()
    }

    func deleteCount(_ count: ModuleCountField) {
        draft.counts.removeAll { $0.id == count.id }
        invalidateValidation()
    }

    /// 队伍光环名称解析（单位摘要）。
    func groupAuraName(_ spellId: Int64) -> String? {
        for field in support.catalog.groupAuraFields(classId: draft.match.classId, specId: draft.match.specId)
        where field.name.split(separator: ".").contains(where: { Int64($0) == spellId }) {
            return field.displayName.components(separatedBy: " / ").first
        }
        return model.iconCatalog.spellName(spellId)
    }

    // MARK: 新建 / 保存 / 删除

    func newModule() {
        let name = model.moduleStore.createNextModuleName()
        var module = ModuleDefinition.createDefault(name: name)
        module.match = ModuleMatch()
        do {
            let saved = try model.moduleStore.save(module)
            reload()
            select(saved.id)
            model.log.append(String(localized: "已新建模块: \(name)"))
            model.restartRuntime(reason: String(localized: "模块已变更"))
        } catch {
            errorMessage = String(localized: "模块操作失败：\(error)")
        }
    }

    func save() {
        guard hasSelection else { return }
        var module = draft
        if module.name.isBlank { module.name = String(localized: "新模块") }
        module.name = module.name.trimmed()
        module.author = module.author.trimmed()
        module.recommendedTalent = module.recommendedTalent.trimmed()
        module.version = AppInfo.version
        module.rules.removeAll { rule in
            rule.condition.isBlank && rule.comment.isBlank && rule.spell.isBlank && rule.unit == nil && rule.unitName.isNilOrBlank
                && rule.macroCondition.isNilOrBlank && (rule.subConditions ?? []).isEmpty && rule.delayMs == nil && rule.logicDelayMs == nil && rule.continueLogic != true
        }
        for (i, adjustment) in module.valueAdjustments.enumerated() where !adjustment.formula.isBlank || adjustment.field.isBlank {
            if adjustment.field.isBlank && !adjustment.formula.isBlank {
                errorMessage = String(localized: "公式动态数值第 \(i + 1) 行缺少数值名称。请在“数值名称”里输入名称，或把公式写成“名称 = 表达式”。")
                return
            }
        }
        module.valueAdjustments.removeAll { $0.field.isBlank }
        if let error = support.upgradeLegacySpellReferences(&module) {
            errorMessage = error
            return
        }
        let service = ModuleDependencyService(paths: model.paths)
        var warning: String?
        do {
            warning = try service.capture(&module)
        } catch {
            errorMessage = String(localized: "保存失败：\(error)")
            return
        }
        do {
            let saved = try model.moduleStore.save(module)
            selectedId = saved.id
            reload()
            if let warning { infoMessage = warning }
            model.log.append(String(localized: "已保存模块: \(saved.name)"))
            model.restartRuntime(reason: String(localized: "模块已保存"))
        } catch {
            errorMessage = String(localized: "保存失败：\(error)")
        }
    }

    func requestDelete() {
        guard hasSelection else { return }
        pendingDeleteName = draft.name
    }

    func confirmDelete() {
        guard hasSelection else { return }
        do {
            try model.moduleStore.delete(original)
            selectedId = nil
            reload()
            model.log.append(String(localized: "已删除模块: \(original.name)"))
            model.restartRuntime(reason: String(localized: "模块已删除"))
        } catch {
            errorMessage = String(localized: "删除失败：\(error)")
        }
        pendingDeleteName = nil
    }

    func discardChanges() {
        draft = original
    }

    func revealFile() {
        if let url = original.fileURL { model.revealInFinder(url) } else { model.openModuleDirectory() }
    }
}
