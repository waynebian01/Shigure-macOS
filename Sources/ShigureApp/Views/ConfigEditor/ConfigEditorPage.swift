import SwiftUI
import ShigureCore

struct ConfigEditorPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: ConfigEditorStore?

    var body: some View {
        Group {
            if let store { ConfigEditorContent(store: store) } else { ProgressView() }
        }
        .onAppear { if store == nil { store = ConfigEditorStore(model: model) } }
    }
}

struct ConfigEditorContent: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ConfigEditorStore
    @State private var tab = 0

    var body: some View {
        HSplitView {
            classList.frame(minWidth: Layout.listMin, idealWidth: Layout.listIdeal, maxWidth: Layout.listMax)
            VStack(spacing: 0) {
                if store.document != nil {
                    HStack {
                        Picker("专精", selection: $store.selectedSpecId) {
                            ForEach(store.specIds, id: \.self) { id in
                                Text("\(store.specName(id)) (\(id))").tag(Int?.some(id))
                            }
                        }
                        .frame(maxWidth: 320)
                        Spacer()
                        Picker("", selection: $tab) {
                            Text("状态").tag(0); Text("光环").tag(1); Text("冷却").tag(2)
                            Text("队伍").tag(3); Text("技能列表").tag(4); Text("物品列表").tag(5)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    .padding(12)
                    Divider()
                    if !store.isModern {
                        ContentUnavailableView("旧版稀疏索引格式", systemImage: "exclamationmark.triangle", description: Text("请先把该职业 Lua 迁移到 states/auras/spells/items/group 结构后再编辑。"))
                    } else {
                        switch tab {
                        case 0: StatesEditor(store: store)
                        case 1: AurasEditor(store: store)
                        case 2: CooldownsEditor(store: store)
                        case 3: GroupEditor(store: store)
                        case 4: SpellsListEditor(store: store)
                        default: ItemsListEditor(store: store)
                        }
                    }
                } else {
                    ContentUnavailableView("请选择职业", systemImage: "slider.horizontal.3", description: Text(store.status))
                }
                Divider()
                footer
            }
            .frame(minWidth: Layout.editorMin)
        }
        .alert("保存失败", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("已保存", isPresented: Binding(get: { store.infoMessage != nil }, set: { if !$0 { store.infoMessage = nil } })) {
            Button("好") { store.infoMessage = nil }
        } message: { Text(store.infoMessage ?? "") }
        .confirmationDialog("当前修改尚未保存，确定丢弃吗？", isPresented: Binding(get: { store.pendingSwitch != nil }, set: { if !$0 { store.pendingSwitch = nil } }), titleVisibility: .visible) {
            Button("丢弃并切换", role: .destructive) { store.confirmSwitch() }
            Button("取消", role: .cancel) { store.pendingSwitch = nil }
        }
    }

    private var classList: some View {
        List(selection: Binding(get: { store.selectedClassId }, set: { if let id = $0 { store.requestSelect(classId: id) } })) {
            ForEach(store.classFiles) { file in
                HStack(spacing: 8) {
                    if let image = model.iconCatalog.classImage(file.classId) {
                        Image(nsImage: image).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Text(file.name)
                }
                .tag(file.classId)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.isDirty ? String(localized: "已修改（未保存）") : store.status).font(.callout).foregroundStyle(store.isDirty ? .orange : .secondary).lineLimit(1)
                if let doc = store.document {
                    Text(doc.fileURL.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if store.isDirty { Button("放弃修改") { store.discard() } }
            Button { store.refreshClassList() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            Button { store.save() } label: { Label(String(localized: store.isSaving ? "保存中…" : "保存"), systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(!store.isDirty || store.isSaving || !store.isModern)
        }
        .padding(10)
    }
}

// MARK: - 状态

struct StatesEditor: View {
    @Bindable var store: ConfigEditorStore
    @State private var category = ClassStateCatalog.categoryState
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $category) {
                ForEach(ClassStateCatalog.topCategories, id: \.self) { Text(ClassStateCatalog.displayName(of: $0)).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            if store.spec.nestedStates {
                let names = store.spec.categorizedStates[category] ?? []
                List(selection: $selection) {
                    ForEach(names, id: \.self) { name in
                        HStack {
                            Text(name)
                            if ConfigEditorStore.fixedStateNames.contains(name) { Text("固定").font(.caption).foregroundStyle(.secondary) }
                            if !ClassStateCatalog.isInCategory(name: name, category: category) { Text("不在目录中").font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            if !ConfigEditorStore.fixedStateNames.contains(name) {
                                Button(role: .destructive) { remove(name) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                            }
                        }
                        .tag(name)
                    }
                    .onMove { from, to in
                        var list = names
                        list.move(fromOffsets: from, toOffset: to)
                        store.spec.categorizedStates[category] = list
                    }
                }
                .listStyle(.inset)
            } else {
                List {
                    ForEach(Array(store.spec.flatStates.enumerated()), id: \.offset) { _, name in Text(name) }
                        .onMove { from, to in store.spec.flatStates.move(fromOffsets: from, toOffset: to) }
                }
                Text("该专精使用扁平 states 列表；保存后将保持扁平格式。").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Menu {
                    ForEach(store.availableStateNames(category: category), id: \.self) { name in
                        Button(name) { add(name) }
                    }
                } label: { Label("添加字段", systemImage: "plus") }
                .disabled(store.availableStateNames(category: category).isEmpty)
                Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(selection == nil)
                Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(selection == nil)
                Spacer()
                Text("锚点/职业/专精 为固定字段；拖动可排序").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private func add(_ name: String) {
        var list = store.spec.categorizedStates[category] ?? []
        if !list.contains(name) { list.append(name) }
        store.spec.categorizedStates[category] = list
    }

    private func remove(_ name: String) {
        store.spec.categorizedStates[category]?.removeAll { $0 == name }
    }

    private func move(_ delta: Int) {
        guard let selection, var list = store.spec.categorizedStates[category], let i = list.firstIndex(of: selection) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        store.spec.categorizedStates[category] = list
    }
}

// MARK: - 光环

struct AurasEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ConfigEditorStore
    @State private var bucket = 0

    static let buckets: [LocalizedStringResource] = ["玩家", "目标·敌对", "目标·友善", "焦点·敌对", "焦点·友善"]

    private var list: Binding<[ClassBlocksStore.AuraEntry]> {
        Binding(get: {
            switch bucket {
            case 0: return store.spec.playerAuras
            case 1: return store.spec.targetHarmfulAuras
            case 2: return store.spec.targetHelpfulAuras
            case 3: return store.spec.focusHarmfulAuras
            default: return store.spec.focusHelpfulAuras
            }
        }, set: { value in
            switch bucket {
            case 0: store.spec.playerAuras = value
            case 1: store.spec.targetHarmfulAuras = value
            case 2: store.spec.targetHelpfulAuras = value
            case 3: store.spec.focusHarmfulAuras = value
            default: store.spec.focusHelpfulAuras = value
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $bucket) {
                ForEach(Array(Self.buckets.enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(8)
            HStack(spacing: 8) {
                Text("图标").frame(width: 32); Text("名称").frame(width: 160, alignment: .leading); Text("spellId").frame(width: 110, alignment: .leading)
                Text("spellIds（逗号分隔）").frame(maxWidth: .infinity, alignment: .leading); Text("maxApps").frame(width: 80, alignment: .leading); Text("").frame(width: 30)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            List {
                ForEach(Array(list.wrappedValue.enumerated()), id: \.offset) { index, aura in
                    HStack(spacing: 8) {
                        SpellIconView(spellId: aura.spellId ?? aura.spellIds.first, name: aura.name)
                        TextField("名称", text: Binding(get: { aura.name }, set: { list.wrappedValue[index].name = $0 })).frame(width: 160)
                        TextField("spellId", text: Binding(get: { aura.spellId.map(String.init) ?? "" }, set: { list.wrappedValue[index].spellId = Int64($0.trimmed()) })).frame(width: 110)
                        TextField("spellIds", text: Binding(get: { aura.spellIds.map(String.init).joined(separator: ", ") }, set: { list.wrappedValue[index].spellIds = Self.parseIds($0) }))
                        TextField("maxApps", text: Binding(get: { aura.maxApps.map(String.init) ?? "" }, set: { list.wrappedValue[index].maxApps = Int($0.trimmed()) })).frame(width: 80)
                        Button(role: .destructive) { list.wrappedValue.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).frame(width: 30)
                    }
                }
                .onMove { from, to in list.wrappedValue.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button { list.wrappedValue.append(ClassBlocksStore.AuraEntry()) } label: { Label("添加光环", systemImage: "plus") }
                Spacer()
                Text("拖动可排序；spellIds 非空时 spellId 作为规范 ID").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    static func parseIds(_ text: String) -> [Int64] {
        text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " }).compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}

struct SpellIconView: View {
    @Environment(AppModel.self) private var model
    let spellId: Int64?
    var name: String? = nil
    var isItem = false

    var body: some View {
        let image = (spellId.flatMap { model.iconCatalog.image(id: $0, isItem: isItem) }) ?? (name.flatMap { model.iconCatalog.image(named: $0) })
        Group {
            if let image { Image(nsImage: image).resizable().clipShape(RoundedRectangle(cornerRadius: 4)) }
            else { RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.2)) }
        }
        .frame(width: 22, height: 22)
        .frame(width: 32)
    }
}

// MARK: - 冷却（技能 + 物品）

struct CooldownsEditor: View {
    @Bindable var store: ConfigEditorStore
    @State private var spellFilter = ""
    @State private var itemFilter = ""

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("技能冷却").font(.headline)
                    TextField("spellId 或名称", text: $spellFilter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Spacer()
                    Text("充能法术连续占 2 格：冷却 → 充能冷却").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                List {
                    ForEach(Array(store.spec.spells.enumerated()).filter { matches($0.element, spellFilter) }, id: \.element.spellId) { index, spell in
                        CooldownSpellRow(store: store, index: index, spell: spell)
                    }
                    .onMove { from, to in if spellFilter.isEmpty { store.spec.spells.move(fromOffsets: from, toOffset: to) } }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Button { store.spec.spells.append(ClassBlocksStore.SpellEntry(name: "", spellId: 0)) } label: { Label("添加技能", systemImage: "plus") }
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: Layout.innerPrimaryMin)
            VStack(spacing: 0) {
                HStack {
                    Text("物品冷却").font(.headline)
                    TextField("itemId 或名称", text: $itemFilter).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                    Spacer()
                }
                .padding(8)
                Text("名称可改为业务别名；图标始终按 itemId 匹配。").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(Array(store.spec.items.enumerated()).filter { itemFilter.isEmpty || String($0.element.itemId ?? 0).contains(itemFilter) || $0.element.name.localizedCaseInsensitiveContains(itemFilter) }, id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            SpellIconView(spellId: item.itemId, name: item.name, isItem: true)
                            TextField("itemId", text: Binding(get: { item.itemId.map(String.init) ?? "" }, set: { store.spec.items[index].itemId = Int64($0.trimmed()) })).frame(width: 90)
                            TextField("名称", text: Binding(get: { item.name }, set: { store.spec.items[index].name = $0 }))
                            Toggle("装备中", isOn: Binding(get: { item.isEquipped }, set: { store.spec.items[index].isEquipped = $0 })).toggleStyle(.checkbox)
                            Button(role: .destructive) { store.spec.items.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Button { store.spec.items.append(ClassBlocksStore.ItemEntry()) } label: { Label("添加物品", systemImage: "plus") }
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: Layout.innerSecondaryMin)
        }
    }

    private func matches(_ spell: ClassBlocksStore.SpellEntry, _ filter: String) -> Bool {
        filter.isEmpty || String(spell.spellId).contains(filter) || spell.name.localizedCaseInsensitiveContains(filter)
    }
}

/// 技能冷却的一行有 9 列（名称、法术 ID、三个复选框、两个数字框、删除），单行摆不进
/// `Layout.innerPrimaryMin`。`HSplitView` 既不认 `idealWidth` 也不会自己让位，分隔条初始就停在
/// 最小宽度上 —— 右边几列被裁掉，用户不拖分隔条就永远够不着。所以这一行自己会折行：
/// 宽度够就排成一行，不够就把开关折到第二行。
struct CooldownSpellRow: View {
    @Bindable var store: ConfigEditorStore
    let index: Int
    let spell: ClassBlocksStore.SpellEntry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                identity
                flags
                deleteButton
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    identity
                    Spacer(minLength: 0)
                    deleteButton
                }
                HStack(spacing: 8) {
                    flags
                    Spacer(minLength: 0)
                }
                .padding(.leading, 36)
            }
        }
    }

    @ViewBuilder
    private var identity: some View {
        SpellIconView(spellId: spell.spellId, name: spell.name)
        TextField("名称", text: Binding(get: { spell.name }, set: { store.spec.spells[index].name = $0 })).frame(width: 140)
        TextField("法术 ID", text: Binding(get: { String(spell.spellId) }, set: { store.spec.spells[index].spellId = Int64($0.trimmed()) ?? 0 })).frame(width: 90)
    }

    @ViewBuilder
    private var flags: some View {
        Toggle("充能", isOn: Binding(get: { spell.charge }, set: { store.spec.spells[index].charge = $0 })).toggleStyle(.checkbox)
        TextField("最大充能", text: Binding(get: { spell.maxCharge.map(String.init) ?? "" }, set: { store.spec.spells[index].maxCharge = Int($0.trimmed()) })).frame(width: 60)
        TextField("施法次数", text: Binding(get: { spell.castCount.map(String.init) ?? "" }, set: { store.spec.spells[index].castCount = Int($0.trimmed()) })).frame(width: 60)
        Toggle("强制已学", isOn: Binding(get: { spell.forcedKnown }, set: { store.spec.spells[index].forcedKnown = $0 })).toggleStyle(.checkbox)
        Toggle("法术书中", isOn: Binding(get: { spell.inSpellBook }, set: { store.spec.spells[index].inSpellBook = $0 })).toggleStyle(.checkbox)
    }

    private var deleteButton: some View {
        Button(role: .destructive) { store.spec.spells.remove(at: index) } label: { Image(systemName: "xmark.circle") }
            .buttonStyle(.borderless)
    }
}

// MARK: - 队伍

struct GroupEditor: View {
    @Bindable var store: ConfigEditorStore

    var body: some View {
        let enabled = store.spec.group != nil
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("启用队伍扫描 (GROUP)", isOn: Binding(get: { enabled }, set: { on in store.spec.group = on ? (store.spec.group ?? ClassBlocksStore.GroupBlocks()) : nil }))
                    if let group = store.spec.group {
                        Stepper(value: Binding(get: { group.num }, set: { store.spec.group?.num = $0 }), in: 1...40) { Text("每成员占用格数 NUM: \(group.num)") }
                        offsetRow("生命值 HEALTH PERCENT", value: group.healthPercent, defaultValue: 1) { store.spec.group?.healthPercent = $0 }
                        offsetRow("职责 ROLE", value: group.role, defaultValue: 2) { store.spec.group?.role = $0 }
                        offsetRow("驱散 DISPEL", value: group.dispel, defaultValue: 3) { store.spec.group?.dispel = $0 }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 230)
            if store.spec.group != nil {
                HStack(spacing: 8) {
                    Text("图标").frame(width: 32); Text("偏移").frame(width: 60, alignment: .leading); Text("名称").frame(width: 160, alignment: .leading)
                    Text("spellId").frame(width: 110, alignment: .leading); Text("spellIds（逗号分隔）").frame(maxWidth: .infinity, alignment: .leading); Text("").frame(width: 30)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                List {
                    ForEach(Array((store.spec.group?.auras ?? []).enumerated()), id: \.offset) { index, aura in
                        HStack(spacing: 8) {
                            SpellIconView(spellId: aura.spellId ?? aura.spellIds.first, name: aura.name)
                            TextField("偏移", text: Binding(get: { String(aura.offset) }, set: { store.spec.group?.auras[index].offset = Int($0.trimmed()) ?? aura.offset })).frame(width: 60)
                            TextField("名称", text: Binding(get: { aura.name }, set: { store.spec.group?.auras[index].name = $0 })).frame(width: 160)
                            TextField("spellId", text: Binding(get: { aura.spellId.map(String.init) ?? "" }, set: { store.spec.group?.auras[index].spellId = Int64($0.trimmed()) })).frame(width: 110)
                            TextField("spellIds", text: Binding(get: { aura.spellIds.map(String.init).joined(separator: ", ") }, set: { store.spec.group?.auras[index].spellIds = AurasEditor.parseIds($0) }))
                            Button(role: .destructive) { store.spec.group?.auras.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).frame(width: 30)
                        }
                    }
                    .onMove { from, to in store.spec.group?.auras.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Button {
                        let next = ((store.spec.group?.auras.map(\.offset).max() ?? 3) + 1)
                        store.spec.group?.auras.append(ClassBlocksStore.GroupAuraEntry(offset: next))
                    } label: { Label("添加队伍光环", systemImage: "plus") }
                    Spacer()
                    Text("偏移为成员内相对格位；保存时按偏移排序").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }

    private func offsetRow(_ title: LocalizedStringResource, value: Int?, defaultValue: Int, set: @escaping (Int?) -> Void) -> some View {
        HStack {
            Toggle(isOn: Binding(get: { value != nil }, set: { set($0 ? (value ?? defaultValue) : nil) })) { Text(title) }
            Spacer()
            if let value {
                Stepper(value: Binding(get: { value }, set: { set($0) }), in: 0...40) { Text("偏移 \(value)") }
            }
        }
    }
}

// MARK: - 技能列表 / 物品列表

struct SpellsListEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ConfigEditorStore
    @State private var filter = ""
    @State private var message: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("技能列表").font(.headline)
                    TextField("法术 ID、索引或名称", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Spacer()
                    Text("来自当前职业 Lua，仅编辑索引 1–100").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                List {
                    ForEach(Array((store.document?.spellsList ?? []).enumerated()).filter { visible($0.element) }, id: \.element.spellId) { index, entry in
                        HStack(spacing: 8) {
                            SpellIconView(spellId: entry.spellId, name: entry.name)
                            TextField("法术 ID", text: Binding(get: { String(entry.spellId) }, set: { store.document?.spellsList[index].spellId = Int64($0.trimmed()) ?? 0 })).frame(width: 100)
                            TextField("索引", text: Binding(get: { String(entry.index) }, set: { store.document?.spellsList[index].index = Int($0.trimmed()) ?? 0 })).frame(width: 60)
                            TextField("名称", text: Binding(get: { entry.name }, set: { store.document?.spellsList[index].name = $0 }))
                            Button(role: .destructive) { store.deleteSpellsListEntry(entry) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
                if let message { Text(message).font(.caption).foregroundStyle(.orange).padding(8) }
            }
            .frame(minWidth: Layout.innerPrimaryMin)
            DatabaseSearchPane(title: "技能数据库", placeholder: "spellId 或名称", suggestions: model.iconCatalog.spellSuggestions, isItem: false,
                               available: model.iconCatalog.isPackageAvailable) { id, name in
                message = store.addSpellFromDatabase(spellId: id, name: name)
            }
            .frame(minWidth: Layout.innerSecondaryMin)
        }
    }

    private func visible(_ e: ClassBlocksStore.SpellsListEntry) -> Bool {
        guard (1...100).contains(e.index) || e.isNew else { return false }
        return filter.isEmpty || String(e.spellId).contains(filter) || String(e.index) == filter || e.name.localizedCaseInsensitiveContains(filter)
    }
}

struct ItemsListEditor: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ConfigEditorStore
    @State private var filter = ""
    @State private var message: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("物品列表").font(.headline)
                    TextField("itemId、索引或名称", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Spacer()
                    Text("来自当前职业 Lua 的 Senkoh.itemsList").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                List {
                    ForEach(Array((store.document?.itemsList ?? []).enumerated()).filter { visible($0.element) }, id: \.element.itemId) { index, entry in
                        HStack(spacing: 8) {
                            SpellIconView(spellId: entry.itemId, name: entry.name, isItem: true)
                            TextField("itemId", text: Binding(get: { String(entry.itemId) }, set: { store.document?.itemsList[index].itemId = Int64($0.trimmed()) ?? 0 })).frame(width: 100)
                            TextField("索引", text: Binding(get: { String(entry.index) }, set: { store.document?.itemsList[index].index = Int($0.trimmed()) ?? 0 })).frame(width: 60)
                            TextField("名称", text: Binding(get: { entry.name }, set: { store.document?.itemsList[index].name = $0 }))
                            Button(role: .destructive) { store.deleteItemsListEntry(entry) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.inset)
                if let message { Text(message).font(.caption).foregroundStyle(.orange).padding(8) }
            }
            .frame(minWidth: Layout.innerPrimaryMin)
            DatabaseSearchPane(title: "物品数据库", placeholder: "itemId 或名称", suggestions: model.iconCatalog.itemSuggestions, isItem: true,
                               available: model.iconCatalog.isItemDatabaseAvailable) { id, name in
                message = store.addItemFromDatabase(itemId: id, name: name)
            }
            .frame(minWidth: Layout.innerSecondaryMin)
        }
    }

    private func visible(_ e: ClassBlocksStore.ItemsListEntry) -> Bool {
        filter.isEmpty || String(e.itemId).contains(filter) || String(e.index) == filter || e.name.localizedCaseInsensitiveContains(filter)
    }
}

/// 技能/物品数据库搜索（来自 .shgpack 名称索引），前 200 条结果。
struct DatabaseSearchPane: View {
    @Environment(AppModel.self) private var model
    let title: LocalizedStringResource
    let placeholder: LocalizedStringKey
    let suggestions: [(id: Int64, name: String)]
    let isItem: Bool
    let available: Bool
    let onAdd: (Int64, String) -> Void
    @State private var query = ""
    @State private var results: [(id: Int64, name: String)] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                TextField(placeholder, text: $query).textFieldStyle(.roundedBorder)
            }
            .padding(8)
            if !available {
                ContentUnavailableView("数据库不可用", systemImage: "externaldrive.badge.xmark", description: Text("请在「通用 → 下载数据包」安装完整数据包"))
            } else {
                List(results, id: \.id) { entry in
                    HStack(spacing: 8) {
                        SpellIconView(spellId: entry.id, isItem: isItem)
                        Text(String(entry.id)).frame(width: 90, alignment: .leading).monospacedDigit()
                        Text(entry.name).lineLimit(1)
                        Spacer()
                        Button("添加") { onAdd(entry.id, entry.name) }.controlSize(.small)
                    }
                }
                .listStyle(.inset)
                Text(query.isEmpty ? String(localized: "输入 ID 或名称开始筛选") : String(localized: "显示前 \(results.count) 条")).font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
        .onChange(of: query) { _, q in
            searchTask?.cancel()
            let source = suggestions
            searchTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
                let text = q.trimmed()
                var found: [(id: Int64, name: String)] = []
                if text.isEmpty {
                    found = Array(source.prefix(200))
                } else if let id = Int64(text) {
                    let prefix = String(id)
                    for s in source where String(s.id).hasPrefix(prefix) { found.append(s); if found.count >= 200 { break } }
                } else {
                    for s in source where s.name.localizedCaseInsensitiveContains(text) { found.append(s); if found.count >= 200 { break } }
                }
                let final = found
                await MainActor.run { results = final }
            }
        }
        .onAppear { results = Array(suggestions.prefix(200)) }
    }
}
