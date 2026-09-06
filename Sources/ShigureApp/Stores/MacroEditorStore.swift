import AppKit
import Observation
import ShigureCore

/// 宏编辑器状态：编辑 Fuyutsui/core/classmacros.lua 的 ClassMacros（对应 C# ClassMacrosEditorControl）。
@MainActor
@Observable
final class MacroEditorStore {
    unowned let model: AppModel

    var document: ClassMacrosStore.Document?
    private var original: ClassMacrosStore.Document?
    private(set) var selectedClassId: Int?
    /// nil = 通用
    var selectedSpecIndex: Int?
    var status = String(localized: "点击刷新以加载 Fuyutsui/core/classmacros.lua")
    var errorMessage: String?
    var infoMessage: String?
    var pendingSwitch: Int?
    var isSaving = false

    init(model: AppModel) {
        self.model = model
        reload()
    }

    var isDirty: Bool {
        guard let document, let original else { return false }
        return document.classes != original.classes
    }

    var selectedClassKey: String? { selectedClassId.map { ClassMacrosStore.classFileKey(classId: $0) } }

    var macros: ClassMacrosStore.ClassMacros {
        get {
            guard let key = selectedClassKey else { return ClassMacrosStore.ClassMacros() }
            return document?.macros(forClassKey: key) ?? ClassMacrosStore.ClassMacros()
        }
        set {
            guard let key = selectedClassKey else { return }
            document?.setMacros(newValue, forClassKey: key)
        }
    }

    func hasClass(_ classId: Int) -> Bool {
        document?.macros(forClassKey: ClassMacrosStore.classFileKey(classId: classId)) != nil
    }

    func reload() {
        let url = model.paths.classMacrosFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            document = nil
            original = nil
            status = String(localized: "未找到 core/classmacros.lua")
            return
        }
        do {
            let doc = try ClassMacrosStore.load(url)
            document = doc
            original = doc
            status = String(localized: "已加载 \(doc.classOrder.count) 个职业宏表")
            if selectedClassId == nil { selectedClassId = ClassNames.allClasses.first?.id }
            selectedSpecIndex = nil
        } catch {
            document = nil
            original = nil
            status = String(localized: "加载失败: \(error)")
        }
    }

    func requestSelect(classId: Int) {
        guard classId != selectedClassId else { return }
        if isDirty { pendingSwitch = classId } else { select(classId: classId) }
    }

    func confirmSwitch() {
        if let target = pendingSwitch {
            document = original
            select(classId: target)
        }
        pendingSwitch = nil
    }

    private func select(classId: Int) {
        selectedClassId = classId
        selectedSpecIndex = nil
        status = String(localized: hasClass(classId) ? "可编辑" : "新建空表（保存后写入）")
    }

    func discard() {
        document = original
    }

    /// 动态宏子列表可选的专精索引（通用 + 已知专精 + 文件中未登记的专精）。
    var specIndexes: [Int] {
        var ids = ClassNames.specs(of: selectedClassId ?? 0).map(\.id)
        for id in macros.dynamicBySpec.keys.sorted() where !ids.contains(id) { ids.append(id) }
        return ids
    }

    func specTitle(_ index: Int?) -> String {
        guard let index else { return String(localized: "通用") }
        guard let classId = selectedClassId, let name = ClassNames.specName(classId: classId, specId: index) else { return String(localized: "专精\(index)") }
        return name
    }

    /// 当前动态宏列表（通用或指定专精）。
    var currentDynamic: [String] {
        get {
            guard let index = selectedSpecIndex else { return macros.dynamicCommon }
            return macros.dynamicBySpec[index] ?? []
        }
        set {
            var m = macros
            if let index = selectedSpecIndex {
                m.dynamicBySpec[index] = newValue
                m.usesSpecDynamicSpells = true
            } else {
                m.dynamicCommon = newValue
            }
            macros = m
        }
    }

    /// 槽位预算提示。
    var slotHint: String {
        let m = macros
        let dynamicCount: Int
        let prefix: String
        if let index = selectedSpecIndex {
            let common = m.dynamicCommon.count
            let spec = m.dynamicBySpec[index]?.count ?? 0
            dynamicCount = common + spec
            prefix = String(localized: "\(specTitle(index))：通用 \(common) + 专精 \(spec)，共 \(dynamicCount) 项")
        } else {
            dynamicCount = m.dynamicCommon.count
            prefix = String(localized: "通用 \(dynamicCount) 项")
        }
        let total = dynamicCount * 30 + m.staticSpells.count + m.specialSpells.count
        return String(localized: "\(prefix)；动态宏 \(dynamicCount * 30) 个（\(dynamicCount) 项 × 30）；静态宏 \(m.staticSpells.count) 个；特殊宏 \(m.specialSpells.count) 个；共 \(total) 个；最多 \(KeymapCatalog.macroSlotCapacity) 个")
    }

    var slotOverflow: Bool {
        let m = macros
        let dynamicCount = m.usesSpecDynamicSpells
            ? m.dynamicCommon.count + (specIndexes.map { m.dynamicBySpec[$0]?.count ?? 0 }.max() ?? 0)
            : m.dynamicCommon.count
        return dynamicCount * 30 + m.staticSpells.count + m.specialSpells.count > KeymapCatalog.macroSlotCapacity
    }

    func save() {
        guard let doc = document else { errorMessage = String(localized: "请先刷新并加载 classmacros.lua。"); return }
        guard let classId = selectedClassId else { errorMessage = String(localized: "请先选择职业。"); return }
        isSaving = true
        status = String(localized: "正在保存本地 Lua…")
        Task {
            do {
                let saved = try ClassMacrosStore.save(doc)
                document = saved
                original = saved
                status = String(localized: "本地 Lua 已保存，正在更新配置并同步游戏…")
                let outcome = await model.afterLuaSaved(relativePath: "core/classmacros.lua", classId: classId)
                status = String(localized: outcome.hasIssue ? "本地已保存并更新配置，但游戏同步失败" : "已保存宏及该职业的模块")
                infoMessage = outcome.notes
            } catch {
                status = String(localized: "保存失败")
                errorMessage = String(localized: "保存失败：\(error)")
            }
            isSaving = false
        }
    }
}
