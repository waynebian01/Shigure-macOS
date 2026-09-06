import SwiftUI
import UniformTypeIdentifiers
import ShigureCore

/// 规则列表：启用 / 图标 / 技能 / 目标 / 宏条件 / 条件 / 注释 / 操作；支持拖拽排序、⌘D 复制。
struct RulesTab: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ModuleEditorStore
    @State private var conditionRuleId: UUID?
    @State private var commentRuleId: UUID?
    @State private var selection: UUID?
    @FocusState private var rulesFocused: Bool
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
            ruleList
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
        .onChange(of: store.selectedId) { _, _ in selection = nil }
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
    private var ruleList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(Array(store.draft.rules.enumerated()), id: \.element.id) { index, rule in
                        listRow(index: index, rule: rule)
                        Divider()
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($rulesFocused)
            .onKeyPress(keys: [.upArrow]) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(keys: [.downArrow]) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                moveSelection(by: 1)
                return .handled
            }
            .onChange(of: selection) { _, id in
                if let id {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func listRow(index: Int, rule: ModuleRule) -> some View {
        let isSelected = selection == rule.id
        return RuleRow(store: store, index: index, rule: rule,
                onEditCondition: { conditionRuleId = rule.id },
                onEditComment: { commentRuleId = rule.id },
                onSelect: { selection = $0 })
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selection = rule.id; rulesFocused = true }
            .id(rule.id)
            .contextMenu { ruleActions(index: index) }
    }

    @ViewBuilder
    private func ruleActions(index: Int) -> some View {
        Button("复制到下一行") { store.duplicateRule(at: index) }
        Button("在下一行添加空白条件") { store.insertBlankRule(after: index) }
        Button("上移") { store.moveRule(from: index, by: -1) }.disabled(index == 0)
        Button("下移") { store.moveRule(from: index, by: 1) }.disabled(index == store.draft.rules.count - 1)
        Divider()
        Button("删除", role: .destructive) { store.deleteRule(at: index) }
    }

    private func moveSelection(by delta: Int) {
        guard !store.draft.rules.isEmpty else { return }
        let current = selection.flatMap { id in store.draft.rules.firstIndex { $0.id == id } }
        let next = current.map { min(max(0, $0 + delta), store.draft.rules.count - 1) } ?? 0
        selection = store.draft.rules[next].id
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
    let onSelect: (UUID) -> Void
    @State private var dropTargeted = false
    @State private var cachedIcon: NSImage?

    var body: some View {
        let presentation = store.rulePresentation(for: rule)
        let issues = presentation.issues
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: RulesTab.columnSpacing) {
                Toggle("", isOn: Binding(get: { rule.enabled }, set: { store.draft.rules[index].enabled = $0 }))
                    .labelsHidden().frame(width: RulesTab.enabledWidth)
                Group {
                    if let image = cachedIcon {
                        Image(nsImage: image).resizable().clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: 32)
                .task(id: rule.spell) {
                    cachedIcon = model.iconCatalog.image(named: rule.spell)
                }
                DeferredRulePicker(title: String(localized: "技能"), selection: rule.spell, label: rule.spell,
                                   options: { [(tag: "", label: "")] + store.spellOptions.map { (tag: $0, label: $0) } }) {
                    store.draft.rules[index].spell = $0
                    store.applySpellChange(ruleIndex: index)
                }
                .frame(width: RulesTab.spellWidth)
                DeferredRulePicker(title: String(localized: "目标"), selection: store.targetTag(rule),
                                   label: localizedReferenceText(store.targetLabel(rule)),
                                   options: { store.targetOptions(for: rule).map { (tag: $0.tag, label: localizedReferenceText($0.label)) } }) {
                    store.setTarget(ruleIndex: index, tag: $0)
                }
                .frame(width: RulesTab.unitWidth)
                DeferredRulePicker(title: String(localized: "宏条件"), selection: MacroConditionText.displayText(rule.macroCondition),
                                   label: MacroConditionText.displayText(rule.macroCondition),
                                   options: { store.macroConditionOptions(for: rule).map { (tag: $0, label: $0) } }) {
                    store.draft.rules[index].macroCondition = $0
                }
                .frame(width: RulesTab.macroWidth)
                Button(action: onEditCondition) {
                    Text(presentation.conditionDisplay).lineLimit(2).frame(minWidth: RulesTab.conditionMinWidth, maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(issues.isEmpty ? Color.primary : Color.red)
                }
                .buttonStyle(.plain)
                .help(issues.isEmpty ? String(localized: "点击编辑条件（当前：\(rule.describeCondition().isBlank ? String(localized: "始终命中") : rule.describeCondition())）") : issues.joined(separator: "\n"))
                HStack(spacing: 6) {
                    Button(action: onEditComment) {
                        Image(systemName: rule.comment.isBlank ? "text.bubble" : "text.bubble.fill")
                            .foregroundStyle(rule.comment.isBlank ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.borderless).help(rule.comment.isBlank ? String(localized: "点击编辑注释") : rule.comment)
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
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .help("拖动调整顺序")
                        .draggable(ModuleRuleDrag(moduleId: store.draft.id, ruleId: rule.id))
                }
                .frame(width: RulesTab.actionsWidth)
            }
            if !issues.isEmpty {
                Text(issues.joined(separator: String(localized: "；")) + String(localized: "。请先添加对应字段。")).font(.caption).foregroundStyle(.red).padding(.leading, 44)
            }
        }
        .padding(.vertical, 2)
        .background(issues.isEmpty ? Color.clear : Color.red.opacity(0.08))
        .overlay(alignment: .bottom) {
            if dropTargeted { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .dropDestination(for: ModuleRuleDrag.self) { items, _ in
            guard let dragged = items.first, dragged.moduleId == store.draft.id,
                  let source = store.draft.rules.firstIndex(where: { $0.id == dragged.ruleId }),
                  let target = store.draft.rules.firstIndex(where: { $0.id == rule.id }), source != target else { return false }
            store.moveRules(from: IndexSet(integer: source), to: source < target ? target + 1 : target)
            onSelect(dragged.ruleId)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

}

private struct ModuleRuleDrag: Codable, Transferable {
    let moduleId: String
    let ruleId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "club.shigure.module-rule"))
    }
}

/// 表格关闭的下拉框只显示当前值；用户打开时才构建菜单选项。
/// 避免每条规则的三个 SwiftUI Picker 在首屏创建、测量整份选项视图树。
struct DeferredRulePicker: NSViewRepresentable {
    let title: String
    let selection: String
    let label: String
    let options: () -> [(tag: String, label: String)]
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> DeferredRulePopUpButton {
        let button = DeferredRulePopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: DeferredRulePopUpButton, context: Context) {
        button.options = options
        button.onSelect = onSelect
        button.setAccessibilityLabel(title)
        button.showSelection(selection, label: label)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DeferredRulePopUpButton, context: Context) -> CGSize? {
        // 宽度由表格列指定，不能再按菜单中最长的选项测量。
        CGSize(width: proposal.width ?? 100, height: nsView.intrinsicContentSize.height)
    }
}

final class DeferredRulePopUpButton: NSPopUpButton {
    var options: () -> [(tag: String, label: String)] = { [] }
    var onSelect: (String) -> Void = { _ in }
    private var selectedValue = ""
    private var selectedLabel = ""

    func showSelection(_ value: String, label: String) {
        guard numberOfItems == 0 || selectedValue != value || selectedLabel != label else { return }
        selectedValue = value
        selectedLabel = label
        removeAllItems()
        addItem(withTitle: label.isEmpty ? " " : label)
        selectedItem?.representedObject = value
    }

    func prepareMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in options() {
            let item = NSMenuItem(title: option.label.isEmpty ? " " : option.label,
                                  action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.tag
            menu.addItem(item)
        }
        // 保留旧模块中暂时不在目录里的值，打开菜单也不能悄悄改写规则。
        if !menu.items.contains(where: { ($0.representedObject as? String) == selectedValue }) {
            let item = NSMenuItem(title: selectedLabel.isEmpty ? " " : selectedLabel,
                                  action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = selectedValue
            menu.addItem(item)
        }
        self.menu = menu
        select(menu.items.first { ($0.representedObject as? String) == selectedValue })
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        selectedValue = value
        selectedLabel = sender.title == " " ? "" : sender.title
        onSelect(value)
    }

    override func mouseDown(with event: NSEvent) {
        prepareMenu()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        prepareMenu()
        super.keyDown(with: event)
    }

    override func performClick(_ sender: Any?) {
        prepareMenu()
        super.performClick(sender)
    }

    override func accessibilityPerformPress() -> Bool {
        prepareMenu()
        return super.accessibilityPerformPress()
    }
}
