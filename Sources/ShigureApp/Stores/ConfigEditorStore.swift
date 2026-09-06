import AppKit
import Observation
import ShigureCore

/// 配置编辑器状态：编辑 Fuyutsui/class/*.lua 的 ClassBlocks / spellsList / itemsList（对应 C# ClassConfigEditorControl）。
@MainActor
@Observable
final class ConfigEditorStore {
    unowned let model: AppModel

    struct ClassFile: Identifiable, Hashable {
        let classId: Int
        let url: URL
        var id: Int { classId }
        var name: String { ClassNames.className(classId) ?? ClassNames.configFileName(classId) }
    }

    private(set) var classFiles: [ClassFile] = []
    private(set) var selectedClassId: Int?
    var document: ClassBlocksStore.Document?
    private var original: ClassBlocksStore.Document?
    var selectedSpecId: Int?
    var status = "点击刷新以加载 Fuyutsui/class"
    var errorMessage: String?
    var infoMessage: String?
    var pendingSwitch: Int?
    var isSaving = false

    init(model: AppModel) {
        self.model = model
        refreshClassList()
    }

    var isDirty: Bool {
        guard let document, let original else { return false }
        return document.specs != original.specs
            || document.spellsList.map { "\($0.spellId)/\($0.index)/\($0.name)" } != original.spellsList.map { "\($0.spellId)/\($0.index)/\($0.name)" }
            || document.itemsList.map { "\($0.itemId)/\($0.index)/\($0.name)" } != original.itemsList.map { "\($0.itemId)/\($0.index)/\($0.name)" }
            || !document.deletedSpellsListOriginalIds.isEmpty || !document.deletedItemsListOriginalIds.isEmpty
    }

    var isModern: Bool { document?.isModernFormat ?? false }

    var specIds: [Int] {
        guard let document else { return [] }
        var ids = ClassNames.specs(of: selectedClassId ?? 0).map(\.id).filter { document.specs[$0] != nil }
        for id in document.specs.keys.sorted() where !ids.contains(id) { ids.append(id) }
        return ids
    }

    func specName(_ specId: Int) -> String {
        guard let classId = selectedClassId, let name = ClassNames.specName(classId: classId, specId: specId) else { return "专精\(specId)" }
        return name
    }

    // MARK: 加载

    func refreshClassList() {
        let dir = model.paths.fuyutsuiClassDirectory
        classFiles = ClassNames.allClasses.compactMap { cls in
            let url = dir.appendingPathComponent("\(ClassNames.configFileName(cls.id)).lua")
            return FileManager.default.fileExists(atPath: url.path) ? ClassFile(classId: cls.id, url: url) : nil
        }
        if classFiles.isEmpty {
            status = "未找到 Fuyutsui/class，请确认数据目录中包含插件源后点击刷新。"
        } else {
            status = "已加载 \(classFiles.count) 个职业文件"
        }
        if let selectedClassId, classFiles.contains(where: { $0.classId == selectedClassId }) {
            load(classId: selectedClassId)
        } else if let first = classFiles.first {
            load(classId: first.classId)
        }
    }

    func requestSelect(classId: Int) {
        guard classId != selectedClassId else { return }
        if isDirty { pendingSwitch = classId } else { load(classId: classId) }
    }

    func confirmSwitch() {
        if let target = pendingSwitch { load(classId: target) }
        pendingSwitch = nil
    }

    func load(classId: Int) {
        guard let file = classFiles.first(where: { $0.classId == classId }) else { return }
        selectedClassId = classId
        do {
            let doc = try ClassBlocksStore.load(file.url)
            document = doc
            original = doc
            selectedSpecId = specIds.first
            status = doc.isModernFormat ? "可编辑" : "此文件仍是旧版稀疏索引格式，请先迁移到 states/auras/spells/items/group 后再编辑。"
            for entry in doc.spellsList { model.iconCatalog.register(spellId: entry.spellId, name: entry.name, overwrite: true) }
            for entry in doc.itemsList { model.iconCatalog.registerItem(itemId: entry.itemId, name: entry.name) }
        } catch {
            document = nil
            original = nil
            status = "加载失败: \(error)"
        }
    }

    func discard() {
        if let classId = selectedClassId { load(classId: classId) }
    }

    // MARK: 当前专精

    var spec: ClassBlocksStore.SpecBlocks {
        get { selectedSpecId.flatMap { document?.specs[$0] } ?? ClassBlocksStore.SpecBlocks() }
        set { if let id = selectedSpecId { document?.specs[id] = newValue } }
    }

    /// 某分类下可添加的目录字段（未使用者）。
    func availableStateNames(category: String) -> [String] {
        let used = Set(spec.categorizedStates[category] ?? [])
        return ClassStateCatalog.names(in: category).filter { !used.contains($0) && $0 != "锚点" }
    }

    static let fixedStateNames: Set<String> = ["锚点", "职业", "专精"]

    // MARK: 技能列表 / 物品列表

    func addSpellFromDatabase(spellId: Int64, name: String) -> String? {
        guard var doc = document else { return "请先选择一个职业文件。" }
        guard doc.isModernFormat else { return "旧版稀疏索引格式暂不支持添加技能。" }
        if let error = validateSpellsList() { return error }
        if doc.spellsList.contains(where: { $0.spellId == spellId }) { return "已有此技能：\(name)（\(spellId)）" }
        let used = Set(doc.spellsList.map(\.index).filter { (1...100).contains($0) })
        guard let next = (1...100).first(where: { !used.contains($0) }) else { return "索引 1–100 已全部使用，无法继续添加技能。" }
        doc.spellsList.append(ClassBlocksStore.SpellsListEntry(spellId: spellId, index: next, name: name))
        document = doc
        model.iconCatalog.register(spellId: spellId, name: name)
        return nil
    }

    func addItemFromDatabase(itemId: Int64, name: String) -> String? {
        guard var doc = document else { return "请先选择一个职业文件。" }
        guard doc.isModernFormat else { return "旧版稀疏索引格式暂不支持添加物品。" }
        if let error = validateItemsList() { return error }
        if doc.itemsList.contains(where: { $0.itemId == itemId }) { return "已有此物品：\(name)（\(itemId)）" }
        let used = Set(doc.itemsList.map(\.index))
        var next = 1
        while used.contains(next) { next += 1 }
        doc.itemsList.append(ClassBlocksStore.ItemsListEntry(itemId: itemId, index: next, name: name))
        document = doc
        model.iconCatalog.registerItem(itemId: itemId, name: name)
        return nil
    }

    func deleteSpellsListEntry(_ entry: ClassBlocksStore.SpellsListEntry) {
        guard var doc = document else { return }
        doc.spellsList.removeAll { $0.spellId == entry.spellId && $0.index == entry.index }
        if entry.originalSpellId != 0 { doc.deletedSpellsListOriginalIds.insert(entry.originalSpellId) }
        document = doc
    }

    func deleteItemsListEntry(_ entry: ClassBlocksStore.ItemsListEntry) {
        guard var doc = document else { return }
        doc.itemsList.removeAll { $0.itemId == entry.itemId && $0.index == entry.index }
        if entry.originalItemId != 0 { doc.deletedItemsListOriginalIds.insert(entry.originalItemId) }
        document = doc
    }

    /// 可编辑的技能条目：索引 1–100（新增行索引也在此区间）。101+ 的条目（种族/通用技能）只读，不参与校验。
    var editableSpellsList: [ClassBlocksStore.SpellsListEntry] {
        (document?.spellsList ?? []).filter { (1...100).contains($0.index) || $0.isNew }
    }

    func validateSpellsList() -> String? {
        guard let doc = document else { return nil }
        let edited = editableSpellsList
        var ids = Set<Int64>()
        for (i, e) in edited.enumerated() {
            if e.spellId <= 0 { return "技能列表第 \(i + 1) 行的法术 ID 必须是正整数。" }
            if !(1...100).contains(e.index) { return "技能列表第 \(i + 1) 行的索引必须是 1–100 的整数。" }
            if e.name.isBlank { return "技能列表第 \(i + 1) 行的名称不能为空。" }
            if !ids.insert(e.spellId).inserted { return "技能列表中的法术 ID \(e.spellId) 重复。" }
        }
        let hidden = Set(doc.spellsList.filter { !(1...100).contains($0.index) }.map(\.spellId))
        if let conflict = edited.first(where: { hidden.contains($0.spellId) })?.spellId {
            return "法术 ID \(conflict) 已被技能列表中索引 101+ 的条目使用。"
        }
        return nil
    }

    func validateItemsList() -> String? {
        guard let doc = document else { return nil }
        var ids = Set<Int64>()
        var indices = Set<Int>()
        for (i, e) in doc.itemsList.enumerated() {
            if e.itemId <= 0 { return "物品列表第 \(i + 1) 行 itemId 必须是正整数。" }
            if e.index <= 0 { return "物品列表第 \(i + 1) 行的索引必须是正整数。" }
            if e.name.isBlank { return "物品列表第 \(i + 1) 行名称不能为空。" }
            if !ids.insert(e.itemId).inserted { return "物品列表 itemId \(e.itemId) 重复。" }
            if !indices.insert(e.index).inserted { return "物品列表索引 \(e.index) 重复。" }
        }
        return nil
    }

    func validateItems() -> String? {
        guard let doc = document else { return nil }
        for specId in doc.specs.keys.sorted() {
            let spec = doc.specs[specId]!
            var ids = Set<Int64>()
            var names = Set<String>()
            var reserved = Set<String>()
            if spec.nestedStates {
                for c in [ClassStateCatalog.categoryState, ClassStateCatalog.categorySpecial, ClassStateCatalog.categoryResource, ClassStateCatalog.categoryConfig] {
                    reserved.formUnion(spec.categorizedStates[c] ?? [])
                }
            } else { reserved.formUnion(spec.flatStates) }
            for (i, item) in spec.items.enumerated() {
                guard let id = item.itemId, id > 0 else { return "专精 \(specId) 的物品第 \(i + 1) 行 itemId 必须是正整数。" }
                if item.name.isBlank { return "专精 \(specId) 的物品第 \(i + 1) 行名称不能为空。" }
                if !ids.insert(id).inserted { return "专精 \(specId) 的物品 itemId \(id) 重复。" }
                if !names.insert(item.name).inserted { return "专精 \(specId) 的物品名称「\(item.name)」重复。" }
                if reserved.contains(item.name) { return "专精 \(specId) 的物品名称「\(item.name)」与状态、特殊、能量或配置开关字段重名。" }
            }
        }
        return nil
    }

    // MARK: 保存

    func save() {
        guard let doc = document, let classId = selectedClassId else { return }
        guard doc.isModernFormat else { errorMessage = "此文件仍是旧版稀疏索引格式，无法用图形编辑器保存。"; return }
        if let e = validateSpellsList() ?? validateItemsList() ?? validateItems() { errorMessage = e; return }
        isSaving = true
        status = "正在保存本地 Lua…"
        Task {
            do {
                let saved = try ClassBlocksStore.save(doc)
                document = saved
                original = saved
                status = "本地 Lua 已保存，正在更新配置并同步游戏…"
                let relative = "class/\(ClassNames.configFileName(classId)).lua"
                let notes = await model.afterLuaSaved(relativePath: relative, classId: classId)
                status = notes.contains("失败") || notes.contains("未完成") ? "本地已保存并更新配置，但游戏同步失败" : "已保存配置及该职业的模块"
                infoMessage = notes
            } catch {
                status = "保存失败"
                errorMessage = "保存失败：\(error)"
            }
            isSaving = false
        }
    }
}
