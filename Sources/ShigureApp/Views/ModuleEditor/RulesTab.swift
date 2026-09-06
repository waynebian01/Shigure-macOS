import SwiftUI
import ShigureCore

/// 规则列表：启用 / 图标 / 技能 / 目标 / 宏条件 / 条件 / 注释 / 操作；支持拖拽排序、⌘D 复制。
struct RulesTab: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ModuleEditorStore
    @State private var conditionRuleId: UUID?
    @State private var commentRuleId: UUID?
    @State private var selection: UUID?
    @Environment(\.undoManager) private var undoManager

    /// 列宽表头与数据行共用。固定列合计必须留得下弹性的「条件」列，
    /// 否则窗口收窄时最右侧的操作列会被裁掉（见 Layout 的宽度预算）。
    static let columnSpacing: CGFloat = 8
    static let enabledWidth: CGFloat = 36
    static let actionsWidth: CGFloat = 88
    static let conditionMinWidth: CGFloat = 54
    static let spellWidth: CGFloat = 140
    static let unitWidth: CGFloat = 104
    static let macroWidth: CGFloat = 104

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RulesTab.columnSpacing) {
                Text("启用").frame(width: RulesTab.enabledWidth)
                Text("图标").frame(width: 32)
                Text("技能").frame(width: RulesTab.spellWidth, alignment: .leading)
                Text("目标").frame(width: RulesTab.unitWidth, alignment: .leading)
                Text("宏条件").frame(width: RulesTab.macroWidth, alignment: .leading)
                Text("条件（点击编辑）").frame(minWidth: RulesTab.conditionMinWidth, maxWidth: .infinity, alignment: .leading)
                Text("").frame(width: RulesTab.actionsWidth)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 4)
            Divider()
            List(selection: $selection) {
                ForEach(Array(store.draft.rules.enumerated()), id: \.element.id) { index, rule in
                    RuleRow(store: store, index: index, rule: rule,
                            onEditCondition: { conditionRuleId = rule.id },
                            onEditComment: { commentRuleId = rule.id })
                        .tag(rule.id)
                        .listRowSeparator(.visible)
                }
                .onMove { source, destination in store.moveRules(from: source, to: destination) }
            }
            .listStyle(.inset)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let index = store.draft.rules.firstIndex(where: { $0.id == id }) {
                    Button("复制到下一行") { store.duplicateRule(at: index) }
                    Button("在下一行添加空白条件") { store.insertBlankRule(after: index) }
                    Button("上移") { store.moveRule(from: index, by: -1) }
                    Button("下移") { store.moveRule(from: index, by: 1) }
                    Divider()
                    Button("删除", role: .destructive) { store.deleteRule(at: index) }
                }
            }
            Divider()
            HStack {
                Button { store.addRule() } label: { Label("添加规则", systemImage: "plus") }
                Button {
                    if let id = selection, let index = store.draft.rules.firstIndex(where: { $0.id == id }) { store.duplicateRule(at: index) }
                } label: { Label("复制", systemImage: "doc.on.doc") }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(selection == nil)
                Button {
                    if let id = selection, let index = store.draft.rules.firstIndex(where: { $0.id == id }) { store.moveRule(from: index, by: -1) }
                } label: { Image(systemName: "arrow.up") }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(selection == nil)
                Button {
                    if let id = selection, let index = store.draft.rules.firstIndex(where: { $0.id == id }) { store.moveRule(from: index, by: 1) }
                } label: { Image(systemName: "arrow.down") }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(selection == nil)
                Spacer()
                Text("规则按顺序判断，第一条命中的规则会执行；拖动行可排序").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in store.undoManager = new }
        .sheet(item: Binding(get: { conditionRuleId.map { RuleSheetTarget(id: $0) } }, set: { conditionRuleId = $0?.id })) { target in
            if let index = store.draft.rules.firstIndex(where: { $0.id == target.id }) {
                let rule = store.draft.rules[index]
                ConditionEditorSheet(
                    context: ConditionEditorContext(store: store, allowSubConditions: true, allowRuleSettings: true),
                    initial: ConditionEditorInitial(condition: rule.condition, subConditions: rule.subConditions ?? [],
                                                    delayMs: rule.delayMs, logicDelayMs: rule.logicDelayMs, continueLogic: rule.continueLogic)
                ) { result in
                    store.draft.rules[index].condition = result.condition
                    store.draft.rules[index].subConditions = result.subConditions.isEmpty ? nil : result.subConditions
                    store.draft.rules[index].delayMs = result.delayMs
                    store.draft.rules[index].logicDelayMs = result.logicDelayMs
                    store.draft.rules[index].continueLogic = result.continueLogic
                }
            }
        }
        .sheet(item: Binding(get: { commentRuleId.map { RuleSheetTarget(id: $0) } }, set: { commentRuleId = $0?.id })) { target in
            if let index = store.draft.rules.firstIndex(where: { $0.id == target.id }) {
                TextEditorSheet(title: "编辑规则注释", text: store.draft.rules[index].comment, confirmTitle: "保存") { text in
                    store.draft.rules[index].comment = text.trimmed()
                }
            }
        }
    }
}

struct RuleSheetTarget: Identifiable { let id: UUID }

struct RuleRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ModuleEditorStore
    let index: Int
    let rule: ModuleRule
    let onEditCondition: () -> Void
    let onEditComment: () -> Void

    var body: some View {
        let issues = store.issues(for: rule)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: RulesTab.columnSpacing) {
                Toggle("", isOn: Binding(get: { rule.enabled }, set: { store.draft.rules[index].enabled = $0 }))
                    .labelsHidden().frame(width: RulesTab.enabledWidth)
                Group {
                    if let image = model.iconCatalog.image(named: rule.spell) {
                        Image(nsImage: image).resizable().clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: 32)
                Picker("", selection: Binding(get: { rule.spell }, set: { store.draft.rules[index].spell = $0; store.applySpellChange(ruleIndex: index) })) {
                    Text("").tag("")
                    ForEach(store.spellOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: RulesTab.spellWidth)
                Picker("", selection: Binding(get: { store.targetTag(rule) }, set: { store.setTarget(ruleIndex: index, tag: $0) })) {
                    ForEach(store.targetOptions(for: rule), id: \.tag) { Text($0.label).tag($0.tag) }
                }
                .labelsHidden().frame(width: RulesTab.unitWidth)
                Picker("", selection: Binding(get: { MacroConditionText.displayText(rule.macroCondition) }, set: { store.draft.rules[index].macroCondition = $0 })) {
                    ForEach(store.macroConditionOptions(for: rule), id: \.self) { Text($0.isEmpty ? " " : $0).tag($0) }
                }
                .labelsHidden().frame(width: RulesTab.macroWidth)
                Button(action: onEditCondition) {
                    Text(conditionDisplay).lineLimit(2).frame(minWidth: RulesTab.conditionMinWidth, maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(issues.isEmpty ? Color.primary : Color.red)
                }
                .buttonStyle(.plain)
                .help(issues.isEmpty ? "点击编辑条件 (当前: \(rule.describeCondition().isBlank ? "始终命中" : rule.describeCondition()))" : issues.joined(separator: "\n"))
                HStack(spacing: 6) {
                    Button(action: onEditComment) {
                        Image(systemName: rule.comment.isBlank ? "text.bubble" : "text.bubble.fill")
                            .foregroundStyle(rule.comment.isBlank ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.borderless).help(rule.comment.isBlank ? "点击编辑注释" : rule.comment)
                    Menu {
                        Button("复制到下一行") { store.duplicateRule(at: index) }
                        Button("在下一行添加空白条件") { store.insertBlankRule(after: index) }
                        Button("上移") { store.moveRule(from: index, by: -1) }.disabled(index == 0)
                        Button("下移") { store.moveRule(from: index, by: 1) }.disabled(index == store.draft.rules.count - 1)
                        Divider()
                        Button("删除", role: .destructive) { store.deleteRule(at: index) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).frame(width: 40)
                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).help("拖动调整顺序")
                }
                .frame(width: RulesTab.actionsWidth)
            }
            if !issues.isEmpty {
                Text(issues.joined(separator: "；") + "。请先添加对应字段。").font(.caption).foregroundStyle(.red).padding(.leading, 44)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(issues.isEmpty ? nil : Color.red.opacity(0.08))
    }

    private var conditionDisplay: String {
        var text = store.support.humanize(rule.condition, spellName: { model.iconCatalog.spellName($0) }, itemName: { model.iconCatalog.itemName($0) })
        if let subs = rule.subConditions, !subs.isEmpty {
            let any = subs.map { store.support.humanize($0, spellName: { model.iconCatalog.spellName($0) }, itemName: { model.iconCatalog.itemName($0) }) }.joined(separator: " | ")
            text = text.isBlank ? "任一(\(any))" : "\(text)  且任一(\(any))"
        }
        if text.isBlank { text = "始终命中" }
        if let d = rule.delayMs, d > 0 { text += "；延迟 \(d) ms" }
        if let d = rule.logicDelayMs, d > 0 { text += "；逻辑延迟 \(d) ms" }
        if rule.continueLogic == true { text += "；继续逻辑" }
        return text
    }
}
