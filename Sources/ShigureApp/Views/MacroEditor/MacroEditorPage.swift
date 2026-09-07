import SwiftUI
import ShigureCore

struct MacroEditorPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: MacroEditorStore?

    var body: some View {
        Group {
            if let store { MacroEditorContent(store: store) } else { ProgressView() }
        }
        .onAppear { if store == nil { store = MacroEditorStore(model: model) } }
    }
}

struct MacroEditorContent: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: MacroEditorStore
    @State private var tab = 0

    var body: some View {
        HSplitView {
            List(selection: Binding(get: { store.selectedClassId }, set: { if let id = $0 { store.requestSelect(classId: id) } })) {
                ForEach(ClassNames.allClasses) { cls in
                    HStack(spacing: 8) {
                        if let image = model.iconCatalog.classImage(cls.id) {
                            Image(nsImage: image).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Text(localizedReferenceText(cls.name) + (store.hasClass(cls.id) ? "" : String(localized: "（无）")))
                    }
                    .tag(cls.id)
                }
            }
            .listStyle(.inset)
            .frame(minWidth: Layout.listMin, idealWidth: Layout.listIdeal, maxWidth: Layout.listMax)
            VStack(spacing: 0) {
                if store.document != nil {
                    Text(store.slotHint).font(.caption).foregroundStyle(store.slotOverflow ? .red : .secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    Picker("", selection: $tab) { Text("动态宏").tag(0); Text("静态宏").tag(1); Text("特殊宏").tag(2) }
                        .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.bottom, 8)
                    Divider()
                    switch tab {
                    case 0: DynamicMacrosEditor(store: store)
                    case 1: ArrayMacrosEditor(store: store, isSpecial: false)
                    default: ArrayMacrosEditor(store: store, isSpecial: true)
                    }
                } else {
                    ContentUnavailableView("未加载 classmacros.lua", systemImage: "command", description: Text(store.status))
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.isDirty ? String(localized: "已修改（未保存）") : store.status).font(.callout).foregroundStyle(store.isDirty ? .orange : .secondary)
                        Text(model.paths.classMacrosFile.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if store.isDirty { Button("放弃修改") { store.discard() } }
                    Button { store.reload() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    Button { store.save() } label: { Label(String(localized: store.isSaving ? "保存中…" : "保存"), systemImage: "square.and.arrow.down") }
                        .keyboardShortcut("s", modifiers: [.command]).buttonStyle(.borderedProminent)
                        .disabled(!store.isDirty || store.isSaving)
                }
                .padding(10)
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
}

struct DynamicMacrosEditor: View {
    @Bindable var store: MacroEditorStore

    private enum DynamicSelection: Hashable {
        case common
        case spec(Int)
    }

    private var selection: Binding<DynamicSelection?> {
        Binding(
            get: {
                store.selectedSpecIndex.map(DynamicSelection.spec) ?? .common
            },
            set: { value in
                guard let value else {
                    store.selectedSpecIndex = nil
                    return
                }
                switch value {
                case .common:
                    store.selectedSpecIndex = nil
                case let .spec(index):
                    store.selectedSpecIndex = index
                }
            }
        )
    }

    var body: some View {
        HSplitView {
            List(selection: selection) {
                Text("通用").tag(DynamicSelection.common)
                ForEach(store.specIndexes, id: \.self) { index in
                    Text(store.specTitle(index) + "（" + String(store.macros.dynamicBySpec[index]?.count ?? 0) + "）").tag(DynamicSelection.spec(index))
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 140, idealWidth: 160, maxWidth: 200)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("图标").frame(width: 32); Text("法术名（每项占 30 个团队点名槽）").frame(maxWidth: .infinity, alignment: .leading); Text("").frame(width: 30)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 6)
                List {
                    ForEach(Array(store.currentDynamic.enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 8) {
                            SpellIconView(spellId: nil, name: name)
                            TextField("法术名", text: Binding(get: { name }, set: { store.currentDynamic[index] = $0 }))
                            Button(role: .destructive) { store.currentDynamic.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).frame(width: 30)
                        }
                    }
                    .onMove { from, to in store.currentDynamic.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.inset)
                Divider()
                HStack {
                    Button { store.currentDynamic.append("") } label: { Label("添加动态宏", systemImage: "plus") }
                    Spacer()
                    Text("创建顺序：动态宏（每项 30 槽）→ 静态宏 → 特殊宏；空字符串保留槽位").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }
}

struct ArrayMacrosEditor: View {
    @Bindable var store: MacroEditorStore
    let isSpecial: Bool
    @State private var editing: Int?

    private var entries: Binding<[ClassMacrosStore.ArrayEntry]> {
        Binding(get: { isSpecial ? store.macros.specialSpells : store.macros.staticSpells },
                set: { value in var m = store.macros; if isSpecial { m.specialSpells = value } else { m.staticSpells = value }; store.macros = m })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("顺序").frame(width: 44); Text("图标").frame(width: 32)
                if isSpecial {
                    Text("技能（手工填写）").frame(width: 160, alignment: .leading)
                } else {
                    Text("单位").frame(width: 60, alignment: .leading); Text("条件").frame(width: 120, alignment: .leading); Text("技能").frame(width: 140, alignment: .leading)
                }
                Text("完整宏").frame(maxWidth: .infinity, alignment: .leading)
                if !isSpecial { Text("注释").frame(width: 140, alignment: .leading) }
                Text("").frame(width: 30)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 6)
            List {
                ForEach(Array(entries.wrappedValue.enumerated()), id: \.offset) { index, entry in
                    let parsed = isSpecial ? SenkohKeymapConverter.parseSpecialMacro(entry.text, comment: entry.comment) : SenkohKeymapConverter.parseStaticMacro(entry.text, comment: entry.comment)
                    HStack(spacing: 8) {
                        Text("\(index + 1)").frame(width: 44).foregroundStyle(.secondary).monospacedDigit()
                        SpellIconView(spellId: nil, name: parsed.spell.isEmpty ? entry.text : parsed.spell)
                        if isSpecial {
                            TextField("技能名", text: Binding(get: { entry.comment ?? "" }, set: { entries.wrappedValue[index].comment = $0.isBlank ? nil : $0 })).frame(width: 160)
                        } else {
                            Text(localizedReferenceText(ReservedUnit.displayText(parsed.unit))).frame(width: 60, alignment: .leading).foregroundStyle(.secondary)
                            Text(parsed.condition).frame(width: 120, alignment: .leading).foregroundStyle(.secondary).lineLimit(1)
                            Text(parsed.spell).frame(width: 140, alignment: .leading).lineLimit(1)
                        }
                        Button { editing = index } label: {
                            Text(entry.text.replacingOccurrences(of: "\n", with: "\\n")).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain).help("点击编辑完整宏")
                        if !isSpecial {
                            TextField("注释", text: Binding(get: { entry.comment ?? "" }, set: { entries.wrappedValue[index].comment = $0.isBlank ? nil : $0 })).frame(width: 140)
                        }
                        Button(role: .destructive) { entries.wrappedValue.remove(at: index) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).frame(width: 30)
                    }
                }
                .onMove { from, to in entries.wrappedValue.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button { entries.wrappedValue.append(ClassMacrosStore.ArrayEntry(text: "")) } label: { Label(String(localized: isSpecial ? "添加特殊宏" : "添加静态宏"), systemImage: "plus") }
                Spacer()
                Text(String(localized: isSpecial ? "特殊宏技能名必须手工填写，固定无目标、无宏条件" : "单位/条件/技能由宏正文解析；注释非空时作为技能名")).font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .sheet(item: Binding(get: { editing.map { IndexTarget(index: $0) } }, set: { editing = $0?.index })) { target in
            if entries.wrappedValue.indices.contains(target.index) {
                TextEditorSheet(title: "编辑完整宏", text: entries.wrappedValue[target.index].text, confirmTitle: "确定", monospaced: true,
                                hint: "支持多行；例如 /cast [@player]荣耀圣令") { text in
                    entries.wrappedValue[target.index].text = text
                }
            }
        }
    }

    struct IndexTarget: Identifiable { let index: Int; var id: Int { index } }
}
