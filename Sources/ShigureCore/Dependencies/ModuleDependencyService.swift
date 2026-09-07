import Foundation

/// 模块依赖快照的捕获与导入（对应 C# ModuleDependencyService）。
/// Capture：以当前本地 Lua 完全覆盖模块 Dependencies。
/// Import：把模块携带而本地缺少的配置与宏追加到本地 Lua，逐模块提交；超过当前宏槽位容量拒绝整个模块；写入失败回滚。
public struct ModuleDependencyService: Sendable {
    public struct ImportResult: Sendable {
        public var configAdded = 0
        public var configUpdated = 0
        public var macrosAdded = 0
        public var changedModules: [String] = []
        public var conflicts: [String] = []
        public var conflictedModuleIds: Set<String> = []
        public var rejected: [(moduleId: String, moduleName: String, reason: String)] = []
        public var sanitizedModules: [ModuleDefinition] = []
        public var removedStateFields: [(moduleName: String, category: String, name: String)] = []
        public var hasChanges: Bool { configAdded > 0 || configUpdated > 0 || macrosAdded > 0 }
    }

    struct MergeCounters {
        var configAdded = 0
        var configUpdated = 0
        var macrosAdded = 0
        var conflicts: [String] = []
        var hasConfigChanges: Bool { configAdded > 0 || configUpdated > 0 }
    }

    static let stateCategories = ClassStateCatalog.topCategories
    static let hiddenFixedStateFields: Set<String> = ["锚点"]
    static let reservedNameCategories = [ClassStateCatalog.categoryState, ClassStateCatalog.categorySpecial, ClassStateCatalog.categoryResource, ClassStateCatalog.categoryConfig]

    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    // MARK: Capture

    /// 返回 nil 表示已携带依赖；返回提示表示模块未同时指定职业和专精。
    public func capture(_ module: inout ModuleDefinition) throws -> String? {
        guard let classId = module.match.classId, let specId = module.match.specId else {
            module.dependencies = nil
            return "模块未同时指定职业和专精，已保存模块逻辑，但未携带配置和宏。"
        }
        let classURL = try resolveClassPath(classId)
        let configDocument = try ClassBlocksStore.load(classURL)
        guard configDocument.isModernFormat else {
            throw LuaStoreError("\(classURL.lastPathComponent) 仍是旧版配置格式，无法随模块保存。")
        }
        guard let spec = configDocument.specs[specId] else {
            throw LuaStoreError("职业 \(classId) 中不存在专精 \(specId) 的配置。")
        }
        let macrosDocument = try ClassMacrosStore.load(paths.classMacrosFile)
        let classKey = ClassMacrosStore.classFileKey(classId: classId)
        guard let macros = macrosDocument.macros(forClassKey: classKey) else {
            throw LuaStoreError("classmacros.lua 中不存在职业 \(classKey) 的宏配置。")
        }
        try Self.ensureMacroCapacity(classId: classId, macros: macros)

        var snapshot = ModuleDependencySnapshot()
        snapshot.classId = classId
        snapshot.specId = specId
        snapshot.config.spec = Self.captureSpec(spec)
        snapshot.config.spellsList = configDocument.spellsList.map { ModuleSpellListEntrySnapshot(spellId: $0.spellId, index: $0.index, name: $0.name) }
        snapshot.config.itemsList = configDocument.itemsList.map { ModuleItemListEntrySnapshot(itemId: $0.itemId, index: $0.index, name: $0.name) }
        snapshot.macros.usesSpecDynamicSpells = macros.usesSpecDynamicSpells
        snapshot.macros.dynamicCommon = macros.dynamicCommon
        snapshot.macros.dynamicForSpec = macros.usesSpecDynamicSpells ? (macros.dynamicBySpec[specId] ?? []) : []
        snapshot.macros.staticSpells = Self.compactMacroSnapshots(macros.staticSpells.map { ModuleMacroEntrySnapshot(text: $0.text, comment: $0.comment) }, isSpecial: false)
        snapshot.macros.specialSpells = Self.compactMacroSnapshots(macros.specialSpells.map { ModuleMacroEntrySnapshot(text: $0.text, comment: $0.comment) }, isSpecial: true)
        module.dependencies = snapshot
        return nil
    }

    static func captureSpec(_ spec: ClassBlocksStore.SpecBlocks) -> ModuleSpecSnapshot {
        var s = ModuleSpecSnapshot()
        s.nestedStates = spec.nestedStates
        s.flatStates = spec.flatStates
        s.categorizedStates = spec.categorizedStates
        s.items = spec.items.compactMap { item in
            guard let id = item.itemId, id > 0, !item.name.isBlank else { return nil }
            return ModuleItemSnapshot(itemId: id, name: item.name, isEquipped: item.isEquipped)
        }
        func auras(_ list: [ClassBlocksStore.AuraEntry]) -> [ModuleAuraSnapshot] {
            list.map { ModuleAuraSnapshot(name: $0.name, spellId: $0.spellId, spellIds: $0.spellIds, maxApps: $0.maxApps) }
        }
        s.playerAuras = auras(spec.playerAuras)
        s.targetHarmfulAuras = auras(spec.targetHarmfulAuras)
        s.targetHelpfulAuras = auras(spec.targetHelpfulAuras)
        s.focusHarmfulAuras = auras(spec.focusHarmfulAuras)
        s.focusHelpfulAuras = auras(spec.focusHelpfulAuras)
        s.spells = spec.spells.map { e in
            var sp = ModuleSpellSnapshot()
            sp.name = e.name; sp.spellId = e.spellId; sp.charge = e.charge; sp.maxCharge = e.maxCharge
            sp.castCount = e.castCount; sp.forcedKnown = e.forcedKnown; sp.inSpellBook = e.inSpellBook
            return sp
        }
        if let g = spec.group {
            var group = ModuleGroupSnapshot()
            group.num = g.num; group.healthPercent = g.healthPercent; group.role = g.role; group.dispel = g.dispel
            group.auras = g.auras.map { a in
                var ga = ModuleGroupAuraSnapshot()
                ga.offset = a.offset; ga.name = a.name; ga.spellId = a.spellId; ga.spellIds = a.spellIds
                return ga
            }
            s.group = group
        }
        return s
    }

    // MARK: Import

    public func importAll(_ modules: [ModuleDefinition]) throws -> ImportResult {
        var result = ImportResult()
        let ordered = modules.sorted { a, b in
            let byName = a.name.caseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return (a.fileURL?.path ?? "").caseInsensitiveCompare(b.fileURL?.path ?? "") == .orderedAscending
        }
        for var module in ordered {
            guard var snapshot = module.dependencies else { continue }
            do {
                try Self.validateSnapshot(module, &snapshot)
                let removed = Self.removeUnknownStateFields(&snapshot.config.spec)
                module.dependencies = snapshot
                if !removed.isEmpty {
                    result.sanitizedModules.append(module)
                    result.removedStateFields.append(contentsOf: removed.map { (module.name, $0.category, $0.name) })
                }
                try importOne(module, snapshot, &result)
            } catch {
                result.rejected.append((module.id, module.name, "\(error)"))
            }
        }
        return result
    }

    private func importOne(_ module: ModuleDefinition, _ snapshot: ModuleDependencySnapshot, _ result: inout ImportResult) throws {
        let classURL = try resolveClassPath(snapshot.classId)
        var configDocument = try ClassBlocksStore.load(classURL)
        guard configDocument.isModernFormat else {
            throw LuaStoreError("\(classURL.lastPathComponent) 仍是旧版配置格式。")
        }
        var localSpec = configDocument.specs[snapshot.specId] ?? ClassBlocksStore.SpecBlocks()
        var macrosDocument = try ClassMacrosStore.load(paths.classMacrosFile)
        let classKey = ClassMacrosStore.classFileKey(classId: snapshot.classId)
        guard var localMacros = macrosDocument.macros(forClassKey: classKey) else {
            throw LuaStoreError("classmacros.lua 中不存在职业 \(classKey) 的宏配置。")
        }

        var counters = MergeCounters()
        Self.mergeSpec(&localSpec, snapshot.config.spec, &counters)
        Self.mergeSpellsList(&configDocument.spellsList, snapshot.config.spellsList, &counters)
        Self.mergeItemsList(&configDocument.itemsList, snapshot.config.itemsList, &counters)
        Self.mergeMacros(&localMacros, specId: snapshot.specId, snapshot.macros, &counters)
        try Self.ensureMacroCapacity(classId: snapshot.classId, macros: localMacros)
        configDocument.specs[snapshot.specId] = localSpec
        macrosDocument.setMacros(localMacros, forClassKey: classKey)

        let prefixed = counters.conflicts.map { "\(module.name): \($0)" }
        if !counters.hasConfigChanges && counters.macrosAdded == 0 {
            result.conflicts.append(contentsOf: prefixed)
            if !counters.conflicts.isEmpty { result.conflictedModuleIds.insert(module.id) }
            return
        }
        try Self.commit(config: configDocument, macros: macrosDocument, saveConfig: counters.hasConfigChanges, saveMacros: counters.macrosAdded > 0)
        result.configAdded += counters.configAdded
        result.configUpdated += counters.configUpdated
        result.macrosAdded += counters.macrosAdded
        result.changedModules.append(module.name)
        result.conflicts.append(contentsOf: prefixed)
        if !counters.conflicts.isEmpty { result.conflictedModuleIds.insert(module.id) }
    }

    static func validateSnapshot(_ module: ModuleDefinition, _ snapshot: inout ModuleDependencySnapshot) throws {
        guard snapshot.schemaVersion >= 1, snapshot.schemaVersion <= ModuleDependencySnapshot.currentSchemaVersion else {
            throw LuaStoreError("不支持依赖快照版本 \(snapshot.schemaVersion)。")
        }
        upgradeLegacyItems(&snapshot)
        guard module.match.classId == snapshot.classId, module.match.specId == snapshot.specId else {
            throw LuaStoreError("依赖快照的职业/专精与模块匹配条件不一致。")
        }
        if let unknown = snapshot.config.spec.categorizedStates.keys.first(where: { !stateCategories.contains($0) }) {
            throw LuaStoreError("依赖快照包含未知状态分类“\(unknown)”。")
        }
        let spec = snapshot.config.spec
        let allAuras = spec.playerAuras + spec.targetHarmfulAuras + spec.targetHelpfulAuras + spec.focusHarmfulAuras + spec.focusHelpfulAuras
        if allAuras.contains(where: { auraSpellIds($0.spellId, $0.spellIds).isEmpty }) {
            throw LuaStoreError("依赖快照包含缺少有效 spellId 的光环。")
        }
        if spec.spells.contains(where: { $0.spellId <= 0 }) {
            throw LuaStoreError("依赖快照包含缺少有效 spellId 的法术。")
        }
        var reserved = Set<String>()
        if spec.nestedStates {
            for category in reservedNameCategories { reserved.formUnion(spec.categorizedStates[category] ?? []) }
        } else {
            reserved.formUnion(spec.flatStates)
        }
        let items = spec.items
        if items.contains(where: { $0.itemId <= 0 || $0.name.isBlank })
            || Set(items.map(\.itemId)).count != items.count
            || Set(items.map(\.name)).count != items.count
            || items.contains(where: { reserved.contains($0.name) }) {
            throw LuaStoreError("依赖快照包含无效或重复的物品 itemId/name。")
        }
        if snapshot.config.spellsList.contains(where: { $0.spellId <= 0 }) {
            throw LuaStoreError("依赖快照包含缺少有效 spellId 的技能列表条目。")
        }
        if snapshot.config.itemsList.contains(where: { $0.itemId <= 0 }) {
            throw LuaStoreError("依赖快照包含缺少有效 itemId 的物品列表条目。")
        }
    }

    static func upgradeLegacyItems(_ snapshot: inout ModuleDependencySnapshot) {
        guard snapshot.schemaVersion == 1 else { return }
        if var legacyNames = snapshot.config.spec.categorizedStates[ClassStateCatalog.categoryItem] {
            for name in legacyNames {
                if let itemId = ClassStateCatalog.legacyItemId(for: name), !snapshot.config.spec.items.contains(where: { $0.itemId == itemId }) {
                    snapshot.config.spec.items.append(ModuleItemSnapshot(itemId: itemId, name: name, isEquipped: false))
                    legacyNames.removeAll { $0 == name }
                }
            }
            snapshot.config.spec.categorizedStates.removeValue(forKey: ClassStateCatalog.categoryItem)
        }
        snapshot.schemaVersion = ModuleDependencySnapshot.currentSchemaVersion
    }

    static func removeUnknownStateFields(_ spec: inout ModuleSpecSnapshot) -> [(category: String, name: String)] {
        var removed: [(String, String)] = []
        if spec.nestedStates {
            for (category, fields) in spec.categorizedStates {
                var kept: [String] = []
                for field in fields {
                    let trimmed = field.trimmed()
                    if isRecognizedStateField(category, trimmed) {
                        kept.append(field)
                    } else if !trimmed.isEmpty {
                        removed.append((category, trimmed))
                    }
                }
                spec.categorizedStates[category] = kept
            }
        } else {
            var kept: [String] = []
            for field in spec.flatStates {
                let trimmed = field.trimmed()
                if hiddenFixedStateFields.contains(trimmed) || ClassStateCatalog.findCategory(trimmed) != nil {
                    kept.append(field)
                } else if !trimmed.isEmpty {
                    removed.append((ClassStateCatalog.categoryState, trimmed))
                }
            }
            spec.flatStates = kept
        }
        return removed.map { (category: $0.0, name: $0.1) }
    }

    static func isRecognizedStateField(_ category: String, _ field: String) -> Bool {
        !field.isEmpty && (ClassStateCatalog.isKnown(category: category, name: field)
            || (category == ClassStateCatalog.categoryState && hiddenFixedStateFields.contains(field)))
    }

    func resolveClassPath(_ classId: Int) throws -> URL {
        let url = paths.classLuaFile(classId: classId)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LuaStoreError("找不到职业配置文件: \(url.path)") }
        guard FileManager.default.fileExists(atPath: paths.classMacrosFile.path) else { throw LuaStoreError("找不到职业宏文件: \(paths.classMacrosFile.path)") }
        return url
    }

    // MARK: 合并

    static func mergeSpec(_ local: inout ClassBlocksStore.SpecBlocks, _ incoming: ModuleSpecSnapshot, _ counters: inout MergeCounters) {
        if local.nestedStates {
            if incoming.nestedStates {
                for category in stateCategories {
                    var list = local.categorizedStates[category] ?? []
                    mergeStrings(&list, incoming.categorizedStates[category] ?? [], &counters)
                    local.categorizedStates[category] = list
                }
            } else {
                var list = local.categorizedStates[ClassStateCatalog.categoryState] ?? []
                mergeStrings(&list, incoming.flatStates, &counters)
                local.categorizedStates[ClassStateCatalog.categoryState] = list
            }
        } else {
            if incoming.nestedStates {
                for category in stateCategories { mergeStrings(&local.flatStates, incoming.categorizedStates[category] ?? [], &counters) }
            } else {
                mergeStrings(&local.flatStates, incoming.flatStates, &counters)
            }
        }
        ClassBlocksStore.relocateSpecialStateFields(&local)

        var reserved = Set<String>()
        if local.nestedStates {
            for category in reservedNameCategories { reserved.formUnion(local.categorizedStates[category] ?? []) }
        } else {
            reserved.formUnion(local.flatStates)
        }
        mergeItems(&local.items, incoming.items, reserved, &counters)
        mergeAuras(&local.playerAuras, incoming.playerAuras, "玩家光环", &counters)
        mergeAuras(&local.targetHarmfulAuras, incoming.targetHarmfulAuras, "目标减益", &counters)
        mergeAuras(&local.targetHelpfulAuras, incoming.targetHelpfulAuras, "目标增益", &counters)
        mergeAuras(&local.focusHarmfulAuras, incoming.focusHarmfulAuras, "焦点减益", &counters)
        mergeAuras(&local.focusHelpfulAuras, incoming.focusHelpfulAuras, "焦点增益", &counters)
        mergeSpells(&local.spells, incoming.spells, &counters)
        // 队伍配置属于本地扫描布局；模块快照只为文件兼容保留，导入时不比较、不修改。
    }

    static func mergeStrings(_ local: inout [String], _ incoming: [String], _ counters: inout MergeCounters) {
        var existing = Set(local)
        for value in incoming.map({ $0.trimmed() }) where !value.isEmpty {
            if existing.insert(value).inserted {
                local.append(value)
                counters.configAdded += 1
            }
        }
    }

    static func mergeAuras(_ local: inout [ClassBlocksStore.AuraEntry], _ incoming: [ModuleAuraSnapshot], _ label: String, _ counters: inout MergeCounters) {
        compactLocalAuras(&local, label, &counters)
        for entry in incoming {
            if let index = local.firstIndex(where: { spellIdentityMatches(auraSpellIds($0.spellId, $0.spellIds), auraSpellIds(entry.spellId, entry.spellIds)) }) {
                mergeAuraMetadata(&local[index], name: entry.name, spellId: entry.spellId, spellIds: entry.spellIds, maxApps: entry.maxApps, label, &counters)
                continue
            }
            local.append(ClassBlocksStore.AuraEntry(name: entry.name, spellId: entry.spellId, spellIds: entry.spellIds, maxApps: entry.maxApps))
            counters.configAdded += 1
        }
    }

    static func compactLocalAuras(_ local: inout [ClassBlocksStore.AuraEntry], _ label: String, _ counters: inout MergeCounters) {
        var index = 0
        while index < local.count {
            let current = local[index]
            if let existingIndex = local[0..<index].firstIndex(where: { spellIdentityMatches(auraSpellIds($0.spellId, $0.spellIds), auraSpellIds(current.spellId, current.spellIds)) }) {
                mergeAuraMetadata(&local[existingIndex], name: current.name, spellId: current.spellId, spellIds: current.spellIds, maxApps: current.maxApps, label, &counters)
                local.remove(at: index)
                counters.configUpdated += 1
                continue
            }
            index += 1
        }
    }

    static func mergeAuraMetadata(_ target: inout ClassBlocksStore.AuraEntry, name: String?, spellId: Int64?, spellIds: [Int64], maxApps: Int?, _ label: String, _ counters: inout MergeCounters) {
        var changed = false
        if target.spellId == nil, let spellId, spellId > 0 {
            target.spellId = spellId
            changed = true
        }
        for id in auraSpellIds(spellId, spellIds) where target.spellId != id && !target.spellIds.contains(id) {
            target.spellIds.append(id)
            changed = true
        }
        if target.maxApps == nil, let maxApps {
            target.maxApps = maxApps
            changed = true
        } else if let localApps = target.maxApps, let maxApps, localApps != maxApps {
            counters.conflicts.append("\(label)“\(displayName(name, spellId))”的 maxApps 存在差异：本地 \(localApps)、模块 \(maxApps)，已保留本地。")
        }
        if target.name.isBlank, let name, !name.isBlank {
            target.name = name
            changed = true
        }
        if changed { counters.configUpdated += 1 }
    }

    static func mergeSpells(_ local: inout [ClassBlocksStore.SpellEntry], _ incoming: [ModuleSpellSnapshot], _ counters: inout MergeCounters) {
        compactLocalSpells(&local, &counters)
        for entry in incoming {
            let name = displayName(entry.name, entry.spellId)
            if let index = local.firstIndex(where: { $0.spellId > 0 && $0.spellId == entry.spellId }) {
                mergeSpellMetadata(&local[index], name: entry.name, charge: entry.charge, maxCharge: entry.maxCharge, castCount: entry.castCount,
                                   forcedKnown: entry.forcedKnown, inSpellBook: entry.inSpellBook, displayName: name, &counters)
                continue
            }
            local.append(ClassBlocksStore.SpellEntry(name: entry.name, spellId: entry.spellId, charge: entry.charge, maxCharge: entry.maxCharge,
                                                     castCount: entry.castCount, forcedKnown: entry.forcedKnown, inSpellBook: entry.inSpellBook))
            counters.configAdded += 1
        }
    }

    static func compactLocalSpells(_ local: inout [ClassBlocksStore.SpellEntry], _ counters: inout MergeCounters) {
        var index = 0
        while index < local.count {
            let current = local[index]
            if let existingIndex = local[0..<index].firstIndex(where: { $0.spellId > 0 && $0.spellId == current.spellId }) {
                mergeSpellMetadata(&local[existingIndex], name: current.name, charge: current.charge, maxCharge: current.maxCharge, castCount: current.castCount,
                                   forcedKnown: current.forcedKnown, inSpellBook: current.inSpellBook, displayName: displayName(current.name, current.spellId), &counters)
                local.remove(at: index)
                counters.configUpdated += 1
                continue
            }
            index += 1
        }
    }

    static func mergeSpellMetadata(_ target: inout ClassBlocksStore.SpellEntry, name: String?, charge: Bool, maxCharge: Int?, castCount: Int?,
                                   forcedKnown: Bool, inSpellBook: Bool, displayName: String, _ counters: inout MergeCounters) {
        var changed = false
        if !target.charge && charge { target.charge = true; changed = true }
        if !target.forcedKnown && forcedKnown { target.forcedKnown = true; changed = true }
        if !target.inSpellBook && inSpellBook { target.inSpellBook = true; changed = true }
        func mergeNullable(_ local: inout Int?, _ incoming: Int?, _ field: String) {
            if local == nil, let incoming {
                local = incoming
                changed = true
            } else if let l = local, let incoming, l != incoming {
                counters.conflicts.append("法术“\(displayName)”的\(field)存在差异：本地 \(l)、模块 \(incoming)，已保留本地。")
            }
        }
        mergeNullable(&target.maxCharge, maxCharge, "最大充能")
        mergeNullable(&target.castCount, castCount, "施法次数")
        if target.name.isBlank, let name, !name.isBlank {
            target.name = name.trimmed()
            changed = true
        }
        if changed { counters.configUpdated += 1 }
    }

    static func mergeItems(_ local: inout [ClassBlocksStore.ItemEntry], _ incoming: [ModuleItemSnapshot], _ reserved: Set<String>, _ counters: inout MergeCounters) {
        compactLocalItems(&local, &counters)
        for item in incoming.sorted(by: { $0.itemId < $1.itemId }) where item.itemId > 0 {
            if let index = local.firstIndex(where: { $0.itemId == item.itemId }) {
                mergeItemMetadata(&local[index], name: item.name, isEquipped: item.isEquipped, &counters)
                continue
            }
            if let byName = local.first(where: { $0.name == item.name }) {
                counters.conflicts.append("物品名称“\(item.name)”的 itemId 不同：本地 \(byName.itemId.map(String.init) ?? "-")、模块 \(item.itemId)，已保留本地。")
                continue
            }
            if reserved.contains(item.name) {
                counters.conflicts.append("物品名称“\(item.name)”与本地状态、特殊、能量或配置开关字段重名，已跳过。")
                continue
            }
            local.append(ClassBlocksStore.ItemEntry(itemId: item.itemId, name: item.name, isEquipped: item.isEquipped))
            counters.configAdded += 1
        }
        local.sort { ($0.itemId ?? Int64.max) < ($1.itemId ?? Int64.max) }
    }

    static func compactLocalItems(_ local: inout [ClassBlocksStore.ItemEntry], _ counters: inout MergeCounters) {
        var index = 0
        while index < local.count {
            let current = local[index]
            guard let id = current.itemId, id > 0 else { index += 1; continue }
            if let existingIndex = local[0..<index].firstIndex(where: { $0.itemId == id }) {
                mergeItemMetadata(&local[existingIndex], name: current.name, isEquipped: current.isEquipped, &counters)
                local.remove(at: index)
                counters.configUpdated += 1
                continue
            }
            index += 1
        }
    }

    static func mergeItemMetadata(_ target: inout ClassBlocksStore.ItemEntry, name: String?, isEquipped: Bool, _ counters: inout MergeCounters) {
        var changed = false
        if !target.isEquipped && isEquipped { target.isEquipped = true; changed = true }
        if target.name.isBlank, let name, !name.isBlank {
            target.name = name.trimmed()
            changed = true
        } else if !target.name.isBlank, let name, !name.isBlank, target.name != name.trimmed() {
            counters.conflicts.append("物品 itemId \(target.itemId.map(String.init) ?? "-") 的名称不同：本地“\(target.name)”、模块“\(name.trimmed())”，已保留本地。")
        }
        if changed { counters.configUpdated += 1 }
    }

    static func mergeSpellsList(_ local: inout [ClassBlocksStore.SpellsListEntry], _ incoming: [ModuleSpellListEntrySnapshot], _ counters: inout MergeCounters) {
        var seen = Set<Int64>()
        var index = 0
        while index < local.count {
            if seen.insert(local[index].spellId).inserted { index += 1 } else { local.remove(at: index); counters.configUpdated += 1 }
        }
        for entry in incoming where !local.contains(where: { $0.spellId == entry.spellId }) {
            // spellId 是跨模块稳定标识；同一 spellId 已存在时保留本地索引/名称。
            local.append(ClassBlocksStore.SpellsListEntry(spellId: entry.spellId, index: entry.index, name: entry.name))
            counters.configAdded += 1
        }
    }

    static func mergeItemsList(_ local: inout [ClassBlocksStore.ItemsListEntry], _ incoming: [ModuleItemListEntrySnapshot], _ counters: inout MergeCounters) {
        var seen = Set<Int64>()
        var index = 0
        while index < local.count {
            if seen.insert(local[index].itemId).inserted { index += 1 } else { local.remove(at: index); counters.configUpdated += 1 }
        }
        for entry in incoming where entry.itemId > 0 && !local.contains(where: { $0.itemId == entry.itemId }) {
            local.append(ClassBlocksStore.ItemsListEntry(itemId: entry.itemId, index: entry.index, name: entry.name))
            counters.configAdded += 1
        }
    }

    static func mergeMacros(_ local: inout ClassMacrosStore.ClassMacros, specId: Int, _ incoming: ModuleMacrosSnapshot, _ counters: inout MergeCounters) {
        var commonNames = Set(local.dynamicCommon.map(normalizeMacroText))
        for value in incoming.dynamicCommon {
            let normalized = normalizeMacroText(value)
            if !normalized.isEmpty, commonNames.insert(normalized).inserted {
                local.dynamicCommon.append(value.trimmed())
                counters.macrosAdded += 1
            }
        }
        if incoming.usesSpecDynamicSpells, !incoming.dynamicForSpec.isEmpty {
            local.usesSpecDynamicSpells = true
            var specMacros = local.dynamicBySpec[specId] ?? []
            var resolved = Set(local.dynamicCommon.map(normalizeMacroText))
            resolved.formUnion(specMacros.map(normalizeMacroText))
            for value in incoming.dynamicForSpec {
                let normalized = normalizeMacroText(value)
                if !normalized.isEmpty, resolved.insert(normalized).inserted {
                    specMacros.append(value.trimmed())
                    counters.macrosAdded += 1
                }
            }
            local.dynamicBySpec[specId] = specMacros
        }
        mergeMacroEntries(&local.staticSpells, incoming.staticSpells, isSpecial: false, &counters)
        mergeMacroEntries(&local.specialSpells, incoming.specialSpells, isSpecial: true, &counters)
    }

    static func mergeMacroEntries(_ local: inout [ClassMacrosStore.ArrayEntry], _ incoming: [ModuleMacroEntrySnapshot], isSpecial: Bool, _ counters: inout MergeCounters) {
        for entry in compactMacroSnapshots(incoming, isSpecial: isSpecial) {
            if let index = local.firstIndex(where: { macrosOverlap($0.text, $0.comment, entry.text, entry.comment, isSpecial: isSpecial) }) {
                if local[index].comment.isNilOrBlank, let comment = entry.comment, !comment.isBlank {
                    local[index].comment = comment
                    counters.macrosAdded += 1
                    continue
                }
                if normalizeMacroText(local[index].text) != normalizeMacroText(entry.text) || commentsConflict(local[index].comment, entry.comment) {
                    counters.conflicts.append("宏“\(macroIdentity(entry.text, entry.comment, isSpecial: isSpecial))”与本地内容不同，已保留本地。")
                }
                continue
            }
            local.append(ClassMacrosStore.ArrayEntry(text: entry.text, comment: entry.comment))
            counters.macrosAdded += 1
        }
    }

    static func compactMacroSnapshots(_ entries: [ModuleMacroEntrySnapshot], isSpecial: Bool) -> [ModuleMacroEntrySnapshot] {
        var result: [ModuleMacroEntrySnapshot] = []
        for entry in entries where !entry.text.isBlank {
            if let index = result.firstIndex(where: { macrosOverlap($0.text, $0.comment, entry.text, entry.comment, isSpecial: isSpecial) }) {
                if result[index].comment.isNilOrBlank, let comment = entry.comment, !comment.isBlank {
                    result[index].comment = comment
                }
                continue
            }
            result.append(entry)
        }
        return result
    }

    static func macrosOverlap(_ leftText: String, _ leftComment: String?, _ rightText: String, _ rightComment: String?, isSpecial: Bool) -> Bool {
        let l = normalizeMacroText(leftText)
        let r = normalizeMacroText(rightText)
        if !l.isEmpty, l == r { return true }
        guard isSpecial else { return false }
        let leftName = leftComment?.trimmed() ?? ""
        let rightName = rightComment?.trimmed() ?? ""
        return !leftName.isEmpty && leftName == rightName
    }

    static func commentsConflict(_ left: String?, _ right: String?) -> Bool {
        let l = left?.trimmed() ?? ""
        let r = right?.trimmed() ?? ""
        return !l.isEmpty && !r.isEmpty && l != r
    }

    static func macroIdentity(_ text: String, _ comment: String?, isSpecial: Bool) -> String {
        let parsed = isSpecial ? SenkohKeymapConverter.parseSpecialMacro(text, comment: comment) : SenkohKeymapConverter.parseStaticMacro(text, comment: comment)
        let spell = parsed.spell.trimmed()
        return spell.isEmpty ? normalizeMacroText(text) : spell
    }

    static func normalizeMacroText(_ value: String?) -> String {
        (value ?? "").replacingOccurrences(of: "\r\n", with: "\n").trimmed()
    }

    /// 对该职业所有专精检查 动态数×30 + 静态 + 特殊 ≤ 当前宏槽位容量。
    public static func ensureMacroCapacity(classId: Int, macros: ClassMacrosStore.ClassMacros) throws {
        for spec in ClassNames.specs(of: classId) {
            let dynamicCount = macros.usesSpecDynamicSpells
                ? macros.dynamicCommon.count + (macros.dynamicBySpec[spec.id]?.count ?? 0)
                : macros.dynamicCommon.count
            let slots = dynamicCount * 30 + macros.staticSpells.count + macros.specialSpells.count
            if slots > KeymapCatalog.macroSlotCapacity {
                let className = ClassNames.className(classId) ?? "职业\(classId)"
                throw LuaStoreError("宏容量超限：\(className) \(spec.name) 合并后 \(slots) 个槽位，最大 \(KeymapCatalog.macroSlotCapacity)。模块未导入。")
            }
        }
    }

    static func commit(config: ClassBlocksStore.Document, macros: ClassMacrosStore.Document, saveConfig: Bool, saveMacros: Bool) throws {
        let originalConfig = saveConfig ? try? Data(contentsOf: config.fileURL) : nil
        let originalMacros = saveMacros ? try? Data(contentsOf: macros.fileURL) : nil
        do {
            if saveConfig { try ClassBlocksStore.save(config) }
            if saveMacros { try ClassMacrosStore.save(macros) }
        } catch {
            var rollbackErrors: [String] = []
            if let originalConfig { do { try AtomicFile.write(originalConfig, to: config.fileURL) } catch let e { rollbackErrors.append("\(e)") } }
            if let originalMacros { do { try AtomicFile.write(originalMacros, to: macros.fileURL) } catch let e { rollbackErrors.append("\(e)") } }
            if !rollbackErrors.isEmpty {
                throw LuaStoreError("模块依赖写入失败，且回滚未完全成功。\(error) / \(rollbackErrors.joined(separator: "; "))")
            }
            throw error
        }
    }

    static func auraSpellIds(_ spellId: Int64?, _ spellIds: [Int64]) -> Set<Int64> {
        var result = Set<Int64>()
        if let spellId, spellId > 0 { result.insert(spellId) }
        for id in spellIds where id > 0 { result.insert(id) }
        return result
    }

    static func spellIdentityMatches(_ left: Set<Int64>, _ right: Set<Int64>) -> Bool {
        !left.isEmpty && !right.isEmpty && !left.isDisjoint(with: right)
    }

    static func displayName(_ name: String?, _ spellId: Int64?) -> String {
        if let name, !name.isBlank { return name.trimmed() }
        return spellId.map(String.init) ?? "未命名"
    }
}
