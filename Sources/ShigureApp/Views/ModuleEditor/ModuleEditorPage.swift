import SwiftUI
import ShigureCore

struct ModuleEditorPage: View {
    @Environment(AppModel.self) private var model
    @State private var store: ModuleEditorStore?

    var body: some View {
        Group {
            if let store {
                ModuleEditorContent(store: store)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if store == nil { store = ModuleEditorStore(model: model) }
        }
        .onChange(of: model.moduleReloadVersion) { _, _ in store?.reload() }
        .onChange(of: model.catalogVersion) { _, _ in store?.refreshCatalogs() }
    }
}

struct ModuleEditorContent: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ModuleEditorStore
    @State private var tab = 0

    var body: some View {
        HSplitView {
            moduleList
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            VStack(spacing: 0) {
                if store.hasSelection {
                    header
                    Divider()
                    Picker("", selection: $tab) {
                        Text("逻辑编辑").tag(0)
                        Text("动态单位").tag(1)
                        Text("动态数值").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    switch tab {
                    case 0: RulesTab(store: store)
                    case 1: UnitsTab(store: store)
                    default: AdjustmentsTab(store: store)
                    }
                } else {
                    ContentUnavailableView("请在左侧选择模块", systemImage: "square.stack.3d.up", description: Text("或点击「新建」创建一个模块"))
                }
                Divider()
                footer
            }
            .frame(minWidth: 640)
        }
        .alert("模块操作失败", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .alert("提示", isPresented: Binding(get: { store.infoMessage != nil }, set: { if !$0 { store.infoMessage = nil } })) {
            Button("好") { store.infoMessage = nil }
        } message: { Text(store.infoMessage ?? "") }
        .confirmationDialog("删除模块「\(store.pendingDeleteName ?? "")」？", isPresented: Binding(get: { store.pendingDeleteName != nil }, set: { if !$0 { store.pendingDeleteName = nil } }), titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.confirmDelete() }
            Button("取消", role: .cancel) { store.pendingDeleteName = nil }
        } message: { Text("模块文件将从模块目录中删除，此操作不可撤销。") }
    }

    private var moduleList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { store.selectedId }, set: { if let id = $0 { store.select(id) } })) {
                ForEach(store.modules) { module in
                    HStack(spacing: 8) {
                        ModuleIconView(classId: module.match.classId, specId: module.match.specId)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.name).lineLimit(1)
                            Text(matchText(module)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .foregroundStyle(store.hasImportIssue(module) ? Color.red : Color.primary)
                    .help(store.hasImportIssue(module) ? (module.hasCompatibleVersion ? "模块依赖导入存在问题，详情见日志" : "模块版本 \(module.version.isEmpty ? "未知" : module.version) 与当前版本不一致，保存后升级") : "")
                    .tag(module.id)
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Button { model.reloadModules() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .help("重新加载模块目录并导入依赖（⌘R）")
                Spacer()
                Link(destination: ReferenceData.moduleSiteURL) { Label("获取模块", systemImage: "arrow.up.right.square") }
            }
            .padding(8)
        }
    }

    private func matchText(_ module: ModuleDefinition) -> String {
        let m = module.match
        let cls = m.classId.map { ClassNames.className($0) ?? "职业\($0)" } ?? "*"
        let spec = m.specId.flatMap { s in m.classId.map { ClassNames.specName(classId: $0, specId: s) ?? "专精\(s)" } } ?? "*"
        return "\(cls) / \(spec) / \(m.partyType ?? "*") / \(m.heroTalent.map(String.init) ?? "*")"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("名称", text: $store.draft.name).textFieldStyle(.roundedBorder)
                TextField("作者", text: $store.draft.author).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                matchPicker("职业", selection: Binding(get: { store.draft.match.classId }, set: { store.setClass($0) })) {
                    Text("任意 (*)").tag(Int?.none)
                    ForEach(ClassNames.allClasses) { Text("\($0.name) (\($0.id))").tag(Int?.some($0.id)) }
                }
                matchPicker("专精", selection: Binding(get: { store.draft.match.specId }, set: { store.setSpec($0) })) {
                    Text("任意 (*)").tag(Int?.none)
                    if let classId = store.draft.match.classId {
                        ForEach(ClassNames.specs(of: classId)) { Text("\($0.name) (\($0.id))").tag(Int?.some($0.id)) }
                    }
                }
                matchPicker("英雄天赋", selection: $store.draft.match.heroTalent) {
                    Text("任意 (*)").tag(Int?.none)
                    if let classId = store.draft.match.classId, let specId = store.draft.match.specId {
                        ForEach(ClassNames.heroTalents(classId: classId, specId: specId)) { Text("\($0.name) (\($0.id))").tag(Int?.some($0.id)) }
                    }
                }
                matchPicker("队伍类型", selection: Binding(get: { ModuleMatch.normalizePartyType(store.draft.match.partyType) ?? "" }, set: { store.draft.match.partyType = $0.isEmpty ? nil : $0 })) {
                    Text("任意 (*)").tag("")
                    Text("单人 (0)").tag("0")
                    Text("团队 (1-40)").tag("1-40")
                    Text("队伍 (46)").tag("46")
                    if let custom = ModuleMatch.normalizePartyType(store.draft.match.partyType), !["0", "1-40", "46"].contains(custom) {
                        Text("自定义 (\(custom))").tag(custom)
                    }
                }
            }
            HStack {
                TextField("推荐天赋（仅说明，不参与匹配）", text: $store.draft.recommendedTalent).textFieldStyle(.roundedBorder)
                Text(store.draft.fileURL?.lastPathComponent ?? "尚未保存").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200)
                Text("版本 \(store.draft.version.isEmpty ? "未知" : store.draft.version)").font(.caption)
                    .foregroundStyle(store.draft.hasCompatibleVersion ? Color.secondary : Color.red)
                    .help(store.draft.hasCompatibleVersion ? "" : "模块版本与当前版本 \(AppInfo.version) 不一致，不参与选择和运行；保存后升级")
            }
        }
        .padding(12)
    }

    private func matchPicker<S: Hashable, C: View>(_ title: String, selection: Binding<S>, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: selection, content: content).labelsHidden().frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Button { store.revealFile() } label: { Label("打开目录", systemImage: "folder") }
            if store.isDirty {
                Text("未保存的修改").font(.caption).foregroundStyle(.orange)
                Button("放弃修改") { store.discardChanges() }
            }
            Spacer()
            Button { store.newModule() } label: { Label("新建", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: [.command])
            Button(role: .destructive) { store.requestDelete() } label: { Label("删除", systemImage: "trash") }
                .disabled(!store.hasSelection)
            Button { store.save() } label: { Label("保存", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!store.hasSelection)
                .buttonStyle(.borderedProminent)
        }
        .padding(10)
    }
}

struct ModuleIconView: View {
    @Environment(AppModel.self) private var model
    let classId: Int?
    let specId: Int?

    var body: some View {
        let image: NSImage? = {
            if let classId, let specId, let img = model.iconCatalog.specImage(classId: classId, specId: specId) { return img }
            if let classId { return model.iconCatalog.classImage(classId) }
            return nil
        }()
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "asterisk.circle").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
