import SwiftUI
import ShigureCore

struct GeneralPage: View {
    @Environment(AppModel.self) private var model
    @State private var testHotkey = "CTRL-NUMPAD1"
    @State private var testResult: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("输入与运行") {
                LabeledContent("触发键") {
                    HStack {
                        Button(model.isRecordingKey ? (model.recordingHint ?? String(localized: "请按任意键...")) : (model.recordingHint ?? model.settings.toggleKey)) {
                            if model.isRecordingKey { model.cancelRecordingToggleKey() } else { model.beginRecordingToggleKey() }
                        }
                        .frame(minWidth: 160)
                        Text("点击后按下新的键盘键或鼠标侧键（Esc 取消）；不支持 Option 与 Command 组合").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("发送模式", selection: $model.settings.sendMode) {
                    ForEach(SendMode.allCases, id: \.self) { mode in Text(mode.localizedName).tag(mode) }
                }
                .onChange(of: model.settings.sendMode) { _, _ in model.restartRuntime(reason: String(localized: "发送模式已变更")) }
                Text("开关：按一次切换；单击：每次触发发送一次；按住：持续按下时运行").font(.caption).foregroundStyle(.secondary)
                Picker("按键注入", selection: $model.settings.keyInjectionMode) {
                    ForEach(KeyInjectionMode.allCases, id: \.self) { mode in Text(mode.localizedName).tag(mode) }
                }
                LabeledContent("测试发送") {
                    HStack {
                        TextField("热键", text: $testHotkey).frame(width: 180)
                        Button("发送") { testResult = model.testSend(hotkey: testHotkey) }
                        if let testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                LabeledContent("逻辑间隔") {
                    HStack {
                        Stepper(value: $model.settings.logicMs, in: 50...2000, step: 10) { Text("\(model.settings.logicMs) ms") }
                        Stepper(value: $model.settings.renderMs, in: 100...2000, step: 50) { Text("渲染 \(model.settings.renderMs) ms") }
                    }
                }
                Toggle("启动时自动开始运行", isOn: $model.settings.autoStartRuntime)
            }

            Section("配置同步") {
                LabeledContent("更新配置") {
                    HStack {
                        Text(model.configStatus).font(.callout).foregroundStyle(model.configStatusIsError ? .orange : .secondary)
                        Spacer()
                        if model.isUpdatingConfig { ProgressView().controlSize(.small) }
                        Button(String(localized: model.isUpdatingConfig ? "更新中…" : "更新配置")) { model.updateConfigFromProject(showFeedback: true) }
                            .disabled(model.isUpdatingConfig)
                    }
                }
                LabeledContent("游戏") {
                    VStack(alignment: .leading) {
                        if let target = model.gameTarget {
                            Text("已检测到游戏进程 pid \(target.pid)，窗口 \(Int(target.bounds.width))×\(Int(target.bounds.height))")
                        } else {
                            Text("未检测到运行中的游戏").foregroundStyle(.secondary)
                        }
                        if let dir = model.addOnsDirectory {
                            HStack {
                                Text(dir.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Button("在 Finder 中显示") { model.revealInFinder(dir) }.controlSize(.small)
                            }
                        }
                    }
                }
                GameIdentifiersEditor()
                GameAppPicker()
            }

            Section("模块") {
                ModuleSelectionCard()
                DefaultModuleCard()
                LabeledContent("获取模块") {
                    HStack {
                        Link("www.shigure.club", destination: ReferenceData.moduleSiteURL)
                        Spacer()
                        Button("打开模块目录") { model.openModuleDirectory() }
                    }
                }
            }

            Section("资源") {
                IconPackCard()
            }

            Section("权限") {
                PermissionRow(title: "屏幕录制", granted: model.hasScreenRecording, detail: "读取游戏窗口像素") {
                    Permissions.requestScreenRecording()
                    Permissions.openSystemSettings(.screenRecording)
                }
                PermissionRow(title: "辅助功能", granted: model.hasAccessibility, detail: "向游戏发送按键") {
                    Permissions.requestAccessibility()
                    Permissions.openSystemSettings(.accessibility)
                }
                PermissionRow(title: "输入监控（可选）", granted: model.hasInputMonitoring, detail: "捕获短促的触发键点击") {
                    Permissions.requestInputMonitoring()
                    Permissions.openSystemSettings(.inputMonitoring)
                }
                Button("重新检查权限") { model.refreshPermissions() }
            }
        }
        .formStyle(.grouped)
    }
}

struct PermissionRow: View {
    let title: LocalizedStringResource
    let granted: Bool
    let detail: LocalizedStringResource
    let action: () -> Void

    var body: some View {
        LabeledContent { 
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(granted ? .green : .orange)
                Text(granted ? String(localized: "已授予") : String(localized: "未授予 · \(String(localized: detail))")).foregroundStyle(.secondary)
                Spacer()
                if !granted { Button("前往设置…", action: action) }
            }
        } label: {
            Text(title)
        }
    }
}

struct GameIdentifiersEditor: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        @Bindable var model = model
        LabeledContent("游戏标识") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("bundle id 或进程名，逗号分隔", text: $text, onCommit: commit)
                    .onAppear { text = model.settings.gameBundleIdentifiers.joined(separator: ", ") }
                Text("默认 com.blizzard.worldofwarcraft；可追加测试服等其它标识。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func commit() {
        let ids = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        model.settings.gameBundleIdentifiers = ids.isEmpty ? ["com.blizzard.worldofwarcraft"] : ids
        model.refreshGameTarget()
    }
}

/// 实时模块选择：自动选择（最匹配）+ 按当前状态过滤的模块；手选保留在设置中。
struct ModuleSelectionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let matches = model.liveModuleMatches
        let selectedId = model.settings.selectedModuleId
        let selectedVisible = selectedId == nil || matches.contains { $0.id == selectedId }
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("模块选择") {
                HStack {
                    Picker("", selection: Binding(
                        get: { selectedVisible ? (selectedId ?? "") : "" },
                        set: { model.selectModule($0.isEmpty ? nil : $0) }
                    )) {
                        Text("自动选择（最匹配）").tag("")
                        ForEach(matches) { module in
                            Text(moduleLabel(module)).tag(module.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 260)
                    Button("刷新模块") { model.reloadModules() }
                }
            }
            Text(model.moduleFilterCaption).font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "可选模块: \(matches.count)") + (selectedVisible ? "" : String(localized: "，已选模块不符合当前筛选"))).font(.caption).foregroundStyle(.secondary)
        }
    }

    func moduleLabel(_ module: ModuleDefinition) -> String {
        let m = module.match
        let cls = m.classId.map { ClassNames.className($0) ?? String(localized: "职业\($0)") } ?? "*"
        let spec = m.specId.flatMap { s in m.classId.map { ClassNames.specName(classId: $0, specId: s) ?? String(localized: "专精\(s)") } } ?? "*"
        return "\(module.name)  ·  \(cls)/\(spec)/\(m.partyType ?? "*")/\(m.heroTalent.map(String.init) ?? "*")"
    }
}

/// 默认模块：4 级联筛选 + 设为默认；列出已保存的默认项。
struct DefaultModuleCard: View {
    @Environment(AppModel.self) private var model
    @State private var classId: Int?
    @State private var specId: Int?
    @State private var heroTalent: Int?
    @State private var partyType: String?
    @State private var moduleId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("默认模块").font(.headline)
            Text("为指定环境设置自动选择时优先使用的模块").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("职业", selection: $classId) {
                    Text("任意").tag(Int?.none)
                    ForEach(ClassNames.allClasses) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .onChange(of: classId) { _, _ in specId = nil; heroTalent = nil }
                Picker("专精", selection: $specId) {
                    Text("任意").tag(Int?.none)
                    if let classId {
                        ForEach(ClassNames.specs(of: classId)) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                }
                .onChange(of: specId) { _, _ in heroTalent = nil }
                Picker("英雄天赋", selection: $heroTalent) {
                    Text("任意").tag(Int?.none)
                    if let classId, let specId {
                        ForEach(ClassNames.heroTalents(classId: classId, specId: specId)) { Text($0.name).tag(Int?.some($0.id)) }
                    }
                }
                Picker("队伍类型", selection: $partyType) {
                    Text("任意").tag(String?.none)
                    Text("单人").tag(String?.some("0"))
                    Text("团队").tag(String?.some("1-40"))
                    Text("队伍").tag(String?.some("46"))
                }
            }
            HStack {
                let candidates = filteredModules
                Picker("", selection: $moduleId) {
                    if candidates.isEmpty {
                        Text("暂无符合筛选的模块").tag("")
                    } else {
                        ForEach(candidates) { module in
                            Text(module.name + (isCurrentDefault(module) ? String(localized: "（当前默认）") : "")).tag(module.id)
                        }
                    }
                }
                .labelsHidden()
                .frame(minWidth: 260)
                .onChange(of: candidates.map(\.id)) { _, ids in if !ids.contains(moduleId) { moduleId = ids.first ?? "" } }
                .onAppear { moduleId = candidates.first?.id ?? "" }
                Button("设为默认") {
                    model.setDefaultModule(DefaultModuleSelection(classId: classId, specId: specId, heroTalent: heroTalent, partyType: partyType, moduleId: moduleId))
                }
                .disabled(moduleId.isEmpty)
            }
            if !model.settings.defaultModules.isEmpty {
                ForEach(Array(model.settings.defaultModules.enumerated()), id: \.offset) { _, selection in
                    HStack {
                        Text(describe(selection)).font(.callout)
                        Spacer()
                        Button(role: .destructive) { model.removeDefaultModule(selection) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var filteredModules: [ModuleDefinition] {
        model.moduleStore.getModules().filter { module in
            let m = module.match
            if let classId, let mc = m.classId, mc != classId { return false }
            if let specId, let ms = m.specId, ms != specId { return false }
            if let heroTalent, let mh = m.heroTalent, mh != heroTalent { return false }
            if let partyType, let mp = ModuleMatch.normalizePartyType(m.partyType), mp != partyType { return false }
            return true
        }
    }

    private func isCurrentDefault(_ module: ModuleDefinition) -> Bool {
        model.settings.defaultModules.contains { $0.hasSameFilter(classId: classId, specId: specId, partyType: partyType, heroTalent: heroTalent) && $0.moduleId == module.id }
    }

    private func describe(_ s: DefaultModuleSelection) -> String {
        let cls = s.classId.map { ClassNames.className($0) ?? String(localized: "职业\($0)") } ?? String(localized: "任意")
        let spec = s.specId.flatMap { sid in s.classId.map { ClassNames.specName(classId: $0, specId: sid) ?? String(localized: "专精\(sid)") } } ?? String(localized: "任意")
        let hero = s.heroTalent.flatMap { h in s.classId.flatMap { c in s.specId.map { ClassNames.heroTalentName(classId: c, specId: $0, talentId: h) ?? "\(h)" } } } ?? String(localized: "任意")
        let party: String
        switch ModuleMatch.normalizePartyType(s.partyType) {
        case "0": party = String(localized: "单人")
        case "1-40": party = String(localized: "团队")
        case "46": party = String(localized: "队伍")
        case nil: party = String(localized: "任意")
        case let other?: party = other
        }
        let name = model.moduleStore.getModulesForDisplay().first { $0.id == s.moduleId }?.name ?? s.moduleId
        return "\(cls) / \(spec) / \(hero) / \(party) → \(name)"
    }
}

/// 正式服/怀旧服共用 bundle id：未运行时由用户指定部署目标。
struct GameAppPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let installed = model.locator.installedGameApps()
        LabeledContent("部署目标") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: Binding(
                    get: { model.settings.gameAppPath ?? "" },
                    set: { model.settings.gameAppPath = $0.isEmpty ? nil : $0; model.refreshGameTarget() }
                )) {
                    Text("自动（运行中的游戏，否则优先正式服 _retail_）").tag("")
                    ForEach(installed, id: \.path) { url in
                        Text(url.deletingLastPathComponent().lastPathComponent + " · " + url.lastPathComponent).tag(url.path)
                    }
                }
                .labelsHidden()
                Text("游戏未运行时用于定位 Interface/AddOns；运行中始终以当前进程为准。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
