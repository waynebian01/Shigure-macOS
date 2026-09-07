import SwiftUI
import ShigureCore

/// 条件编辑器上下文：字段目录 + 技能/物品选项。
@MainActor
struct ConditionEditorContext {
    let fields: [ConditionField]
    let spells: [ConditionSpell]
    let items: [ConditionItem]
    let allowSubConditions: Bool
    let allowRuleSettings: Bool

    init(store: ModuleEditorStore, allowSubConditions: Bool, allowRuleSettings: Bool) {
        fields = store.support.conditionFields(module: store.draft, includeRuleSettings: allowRuleSettings)
        spells = store.support.catalog.conditionSpells(classId: store.draft.match.classId)
        items = store.support.catalog.conditionItems(classId: store.draft.match.classId)
        self.allowSubConditions = allowSubConditions
        self.allowRuleSettings = allowRuleSettings
    }

    init(fields: [ConditionField], spells: [ConditionSpell], items: [ConditionItem], allowSubConditions: Bool, allowRuleSettings: Bool) {
        self.fields = fields
        self.spells = spells
        self.items = items
        self.allowSubConditions = allowSubConditions
        self.allowRuleSettings = allowRuleSettings
    }

    func field(named name: String) -> ConditionField? {
        let normalized = ModuleEditorSupport.normalizeFieldName(name)
        return fields.first { $0.name == name || $0.name == normalized }
    }
}

struct ConditionEditorInitial {
    var condition: String
    var subConditions: [String]
    var delayMs: Int?
    var logicDelayMs: Int?
    var continueLogic: Bool?
}

struct ConditionEditorResult {
    var condition: String
    var subConditions: [String]
    var delayMs: Int?
    var logicDelayMs: Int?
    var continueLogic: Bool?
}

/// 一行条件（可视化）。
struct ConditionRowDraft: Identifiable {
    let id = UUID()
    var orWithPrevious = false
    var category: ConditionFieldCategory = .state
    var classification: String = ""
    var field: String = ""
    var op: String = "=="
    var value: String = ""
}

struct ConditionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let context: ConditionEditorContext
    let initial: ConditionEditorInitial
    let onConfirm: (ConditionEditorResult) -> Void

    @State private var rows: [ConditionRowDraft] = []
    @State private var subConditions: [String] = []
    @State private var editingSub: SubConditionTarget?
    @State private var warning: String?
    @State private var pendingConfirm: ConditionEditorResult?

    static let allOperators = ["==", "!=", ">", ">=", "<", "<=", "in", "not in"]
    static let spellOperators = ["==", "!="]
    static let boolOperators = ["==", "!="]
    static let textOperators = ["==", "!=", "in", "not in"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("编辑条件").font(.title3.bold())
                Spacer()
                Button { rows.append(ConditionRowDraft(orWithPrevious: false)) } label: { Label("添加条件", systemImage: "plus") }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    header
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(index: index, row: row)
                    }
                    if rows.isEmpty {
                        Text("尚无条件（始终命中）。点击「添加条件」。").foregroundStyle(.secondary).padding()
                    }
                }
                .padding(12)
            }
            if context.allowSubConditions {
                Divider()
                subConditionsSection
            }
            Divider()
            HStack {
                Text("预览: \(preview)").font(.callout).foregroundStyle(.secondary).lineLimit(2).help(preview)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            HStack {
                if let warning { Text(warning).font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确定") { confirm() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 1000, idealWidth: 1080, minHeight: context.allowSubConditions ? 620 : 460)
        .onAppear(perform: seed)
        .sheet(item: $editingSub) { target in
            ConditionEditorSheet(
                context: ConditionEditorContext(fields: context.fields.filter { $0.category != .shigure }, spells: context.spells, items: context.items, allowSubConditions: false, allowRuleSettings: false),
                initial: ConditionEditorInitial(condition: target.index.map { subConditions[$0] } ?? "", subConditions: [], delayMs: nil, logicDelayMs: nil, continueLogic: nil)
            ) { result in
                if let i = target.index {
                    if result.condition.isBlank { subConditions.remove(at: i) } else { subConditions[i] = result.condition }
                } else if !result.condition.isBlank {
                    subConditions.append(result.condition)
                }
            }
        }
        .confirmationDialog(pendingConfirmMessage, isPresented: Binding(get: { pendingConfirm != nil }, set: { if !$0 { pendingConfirm = nil } }), titleVisibility: .visible) {
            Button("继续") { if let r = pendingConfirm { onConfirm(r); dismiss() } }
            Button("取消", role: .cancel) { pendingConfirm = nil }
        }
    }

    private var pendingConfirmMessage: String {
        let incomplete = rows.filter { ($0.field.isEmpty) != ($0.value.isEmpty) }.count
        if incomplete > 0 { return String(localized: "有 \(incomplete) 行不完整(字段或值为空), 将被忽略。继续？") }
        return String(localized: "当前条件为空, 将清除该规则的条件(始终命中)。继续？")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("连接").frame(width: 60)
            Text("类型").frame(width: 100, alignment: .leading)
            Text("分类").frame(width: 110, alignment: .leading)
            Text("字段").frame(maxWidth: .infinity, alignment: .leading)
            Text("判断").frame(width: 80, alignment: .leading)
            Text("值").frame(width: 220, alignment: .leading)
            Text("").frame(width: 30)
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: 行

    private func rowView(index: Int, row: ConditionRowDraft) -> some View {
        let field = context.field(named: row.field)
        let isRuleSetting = row.category == .shigure
        return HStack(spacing: 8) {
            Group {
                if index == 0 || isRuleSetting {
                    Text("").frame(width: 60)
                } else {
                    FixedPopUpPicker(
                        options: [PopUpOption(false, String(localized: "且")), PopUpOption(true, String(localized: "或"))],
                        selection: Binding(get: { rows[index].orWithPrevious }, set: { rows[index].orWithPrevious = $0 })
                    )
                    .frame(width: 60)
                }
            }
            FixedPopUpPicker(
                options: availableCategories.map { PopUpOption($0, localizedReferenceText($0.rawValue)) },
                selection: Binding(get: { rows[index].category }, set: { newValue in
                    rows[index].category = newValue
                    rows[index].classification = classifications(for: newValue).first ?? ""
                    rows[index].field = ""
                    rows[index].value = ""
                    rows[index].op = "=="
                })
            )
            .frame(width: 100)
            FixedPopUpPicker(
                options: classifications(for: row.category).map { PopUpOption($0, $0.isEmpty ? String(localized: "未分类") : localizedReferenceText($0)) },
                selection: Binding(get: { rows[index].classification }, set: { rows[index].classification = $0; rows[index].field = "" })
            )
            .frame(width: 110)
            .disabled(![.state, .aura, .spell].contains(row.category))
            FieldPicker(fields: fieldOptions(for: row), selection: Binding(get: { rows[index].field }, set: { name in
                rows[index].field = name
                let f = context.field(named: name)
                let ops = operators(for: f)
                if !ops.contains(rows[index].op) { rows[index].op = ops[0] }
                if isRuleSettingField(name) { rows[index].op = "==" }
                rows[index].value = defaultValue(for: f, current: rows[index].value)
            }), customName: row.field.isEmpty || field != nil ? nil : row.field, iconProvider: { model.iconCatalog.image(named: $0) })
            .frame(maxWidth: .infinity)
            if isRuleSetting {
                Text("=").frame(width: 80)
            } else {
                FixedPopUpPicker(
                    options: operators(for: field).map { PopUpOption($0, $0) },
                    selection: Binding(get: { rows[index].op }, set: { rows[index].op = $0; if $0 == "in" || $0 == "not in" { rows[index].value = ConditionEditorSheet.normalizeInValue(rows[index].value) } })
                )
                .frame(width: 80)
            }
            valueEditor(index: index, row: row, field: field).frame(width: 220)
            Button(role: .destructive) { rows.remove(at: index) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).frame(width: 30)
        }
        .padding(.vertical, 2)
    }

    private var availableCategories: [ConditionFieldCategory] {
        var list: [ConditionFieldCategory] = [.state]
        if context.allowRuleSettings { list.append(.shigure) }
        list += [.aura, .spell, .dynamicUnit, .dynamicValue]
        return list
    }

    private func classifications(for category: ConditionFieldCategory) -> [String] {
        switch category {
        case .state:
            var list = ClassStateCatalog.topCategories
            for f in context.fields where f.category == .state {
                if let c = f.classification, !list.contains(c) { list.append(c) }
            }
            return list
        case .spell: return [CooldownConditionClassifications.spell, CooldownConditionClassifications.item]
        case .aura:
            var list: [String] = []
            for f in context.fields where f.category == .aura { if let c = f.classification, !list.contains(c) { list.append(c) } }
            return list.isEmpty ? [""] : list
        default: return [""]
        }
    }

    private func fieldOptions(for row: ConditionRowDraft) -> [ConditionField] {
        context.fields.filter { f in
            guard f.category == row.category else { return false }
            if [.state, .aura, .spell].contains(row.category) {
                return (f.classification ?? "") == row.classification || row.classification.isEmpty
            }
            return true
        }
    }

    private func isRuleSettingField(_ name: String) -> Bool {
        [ShigureConditionFields.delay, ShigureConditionFields.logicDelay, ShigureConditionFields.continueLogic].contains(name)
    }

    private func operators(for field: ConditionField?) -> [String] {
        guard let field else { return Self.allOperators }
        if isRuleSettingField(field.name) { return ["=="] }
        if SpellIdConditionFields.contains(field.name) || ItemIdConditionFields.contains(field.name) { return Self.spellOperators }
        if !field.isCustom && field.type == .bool { return Self.boolOperators }
        if !field.isCustom && field.type == .string { return Self.textOperators }
        return Self.allOperators
    }

    private func defaultValue(for field: ConditionField?, current: String) -> String {
        guard let field else { return current }
        if field.name == ShigureConditionFields.continueLogic { return current.isEmpty ? "true" : current }
        if field.type == .bool { return Self.isFalseText(current) ? "false" : "true" }
        if field.name == "首领战" { return current.isEmpty ? "0" : current }
        if SpellIdConditionFields.contains(field.name) { return current.isEmpty ? (context.spells.first.map { String($0.spellId) } ?? "") : current }
        if ItemIdConditionFields.contains(field.name) { return current.isEmpty ? (context.items.first.map { String($0.itemId) } ?? "") : current }
        if field.type == .int { return Int(current.trimmed()).map(String.init) ?? "0" }
        return current
    }

    @ViewBuilder
    private func valueEditor(index: Int, row: ConditionRowDraft, field: ConditionField?) -> some View {
        let binding = Binding(get: { rows[index].value }, set: { rows[index].value = $0 })
        if let field, SpellIdConditionFields.contains(field.name) {
            IdPicker(options: context.spells.map { IdOption(id: $0.spellId, label: "\($0.index). \($0.name) / \($0.spellId)", index: $0.index) }, selection: binding, missingFormat: String(localized: "spellId %@（不存在）"), iconProvider: { model.iconCatalog.spellImage($0) })
        } else if let field, ItemIdConditionFields.contains(field.name) {
            IdPicker(options: context.items.map { IdOption(id: $0.itemId, label: "\($0.index). \($0.name) / \($0.itemId)", index: $0.index) }, selection: binding, missingFormat: String(localized: "itemId %@（不存在）"), iconProvider: { model.iconCatalog.itemImage($0) })
        } else if let field, field.name == "首领战" {
            FixedPopUpPicker(options: bossOptions(current: row.value), selection: binding)
        } else if let field, !field.isCustom, field.type == .bool || field.name == ShigureConditionFields.continueLogic {
            FixedPopUpPicker(
                options: [PopUpOption("true", String(localized: "是 (true)")), PopUpOption("false", String(localized: "否 (false)"))],
                selection: Binding(get: { Self.isFalseText(rows[index].value) ? "false" : "true" }, set: { rows[index].value = $0 })
            )
        } else {
            HStack(spacing: 4) {
                TextField(String(localized: row.op == "in" || row.op == "not in" ? "1, 2, 3" : "值"), text: binding)
                if let field, field.name.contains("施法") || field.name.contains("引导"), let n = Int(row.value) {
                    Text(String(localized: "约\(String(format: "%.1f", Double(n) / 10))秒")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func bossOptions(current: String) -> [PopUpOption<String>] {
        var options = [PopUpOption("0", String(localized: "0 → 非首领战 / -"))]
        options += ReferenceData.bossOptions.map { PopUpOption(String($0.number), $0.display) }
        if Int(current) == nil || (Int(current)! != 0 && !ReferenceData.bossOptions.contains { String($0.number) == current }) {
            options.append(PopUpOption(current, current.isEmpty ? "" : String(localized: "\(current)（未知）")))
        }
        return options
    }

    // MARK: 子条件

    private var subConditionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("子条件 (满足任一即可, 与主条件为「且」关系)").font(.headline)
            List {
                ForEach(Array(subConditions.enumerated()), id: \.offset) { index, sub in
                    Text(sub).lineLimit(2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editingSub = SubConditionTarget(index: index) }
                        .contextMenu {
                            Button("编辑") { editingSub = SubConditionTarget(index: index) }
                            Button("删除", role: .destructive) { subConditions.remove(at: index) }
                        }
                }
            }
            .frame(height: 110)
            HStack {
                Button("添加子条件") { editingSub = SubConditionTarget(index: nil) }
                Text("双击编辑，右键删除").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    struct SubConditionTarget: Identifiable {
        let index: Int?
        var id: Int { index ?? -1 }
    }

    // MARK: 生成

    private var preview: String {
        var text = ConditionExpression.build(terms(excludingRuleSettings: true))
        if !subConditions.isEmpty { text += (text.isEmpty ? "" : "  ") + String(localized: "且任一(\(subConditions.joined(separator: " | ")))") }
        if text.isEmpty { text = String(localized: "(无条件, 始终命中)") }
        let (delay, logicDelay, cont, _) = ruleSettings()
        if let delay, delay > 0 { text += String(localized: "；延迟 \(delay) ms") }
        if let logicDelay, logicDelay > 0 { text += String(localized: "；逻辑延迟 \(logicDelay) ms") }
        if cont == true { text += String(localized: "；继续逻辑") }
        return text
    }

    private func terms(excludingRuleSettings: Bool) -> [ConditionTerm] {
        rows.filter { !(excludingRuleSettings && isRuleSettingField($0.field)) }
            .map { ConditionTerm(field: $0.field, op: $0.op, value: $0.value, orWithPrevious: $0.orWithPrevious) }
    }

    /// 返回 (延迟, 逻辑延迟, 继续逻辑, 错误)。
    private func ruleSettings() -> (Int?, Int?, Bool?, String?) {
        enum DelayRead { case success(Int?), failure(String) }
        func readDelay(_ name: String, _ display: String) -> DelayRead {
            let matches = rows.filter { $0.field == name }
            if matches.count > 1 { return .failure(String(localized: "每条规则只能设置一个「\(display)」。请删除多余的 Shigure \(display)行。")) }
            guard let row = matches.first else { return .success(nil) }
            let text = row.value.trimmed()
            guard let value = Int(text.isEmpty ? "0" : text), value >= 0 else { return .failure(String(localized: "\(display)必须是 0 到 2147483647 之间的整数，单位为 ms。")) }
            return .success(value > 0 ? value : nil)
        }
        var error: String?
        var delay: Int?
        var logicDelay: Int?
        switch readDelay(ShigureConditionFields.delay, String(localized: "延迟")) {
        case .success(let v): delay = v
        case .failure(let e): error = e
        }
        switch readDelay(ShigureConditionFields.logicDelay, String(localized: "逻辑延迟")) {
        case .success(let v): logicDelay = v
        case .failure(let e): error = error ?? e
        }
        let contRows = rows.filter { $0.field == ShigureConditionFields.continueLogic }
        if contRows.count > 1 { error = error ?? String(localized: "每条规则只能设置一个「继续逻辑」。请删除多余的 Shigure 继续逻辑行。") }
        var cont: Bool?
        if let first = contRows.first, !Self.isFalseText(first.value) { cont = true }
        return (delay, logicDelay, cont, error)
    }

    private func confirm() {
        let (delay, logicDelay, cont, error) = ruleSettings()
        if let error {
            warning = error
            return
        }
        let condition = ConditionExpression.build(terms(excludingRuleSettings: true))
        let result = ConditionEditorResult(condition: condition, subConditions: subConditions.map { $0.trimmed() }.filter { !$0.isEmpty },
                                           delayMs: delay, logicDelayMs: logicDelay, continueLogic: cont)
        let incomplete = rows.filter { !isRuleSettingField($0.field) && ($0.field.isEmpty != $0.value.isEmpty) }
        if !incomplete.isEmpty {
            pendingConfirm = result
            return
        }
        if !initial.condition.isBlank || !initial.subConditions.isEmpty, condition.isBlank, result.subConditions.isEmpty {
            pendingConfirm = result
            return
        }
        onConfirm(result)
        dismiss()
    }

    private func seed() {
        var seeded: [ConditionRowDraft] = []
        for term in ConditionExpression.parse(initial.condition) {
            let field = context.field(named: term.field)
            var row = ConditionRowDraft(orWithPrevious: term.orWithPrevious)
            row.category = field?.category ?? .state
            row.classification = field?.classification ?? ""
            row.field = field?.name ?? term.field
            row.op = term.op.trimmed().lowercased().collapsingWhitespace()
            row.value = (row.op == "in" || row.op == "not in") ? Self.normalizeInValue(term.value) : term.value
            seeded.append(row)
        }
        if context.allowRuleSettings {
            if let d = initial.delayMs, d > 0 { seeded.append(ruleSettingRow(ShigureConditionFields.delay, String(d))) }
            if let d = initial.logicDelayMs, d > 0 { seeded.append(ruleSettingRow(ShigureConditionFields.logicDelay, String(d))) }
            if initial.continueLogic == true { seeded.append(ruleSettingRow(ShigureConditionFields.continueLogic, "true")) }
        }
        rows = seeded
        subConditions = initial.subConditions
    }

    private func ruleSettingRow(_ name: String, _ value: String) -> ConditionRowDraft {
        var row = ConditionRowDraft()
        row.category = .shigure
        row.field = name
        row.op = "=="
        row.value = value
        return row
    }

    static func isFalseText(_ text: String) -> Bool {
        let t = text.trimmed().lowercased()
        return t == "false" || t == "no" || t == "否" || t == "0" || t.hasPrefix("否")
    }

    static func normalizeInValue(_ text: String) -> String {
        var t = text.trimmed()
        if t.hasPrefix("(") && t.hasSuffix(")") { t = String(t.dropFirst().dropLast()).trimmed() }
        return t
    }
}

// MARK: - 固定宽度下拉（NSPopUpButton）

/// macOS 的 SwiftUI Picker 按最长菜单项自适应宽度、忽略 frame 提议的宽度，
/// 同一列的下拉因此参差不齐；直接包 NSPopUpButton 让控件吃满列宽。
struct PopUpOption<Tag: Hashable> {
    let tag: Tag
    let title: String
    var image: NSImage?
    var titleColor: NSColor?

    init(_ tag: Tag, _ title: String, image: NSImage? = nil, titleColor: NSColor? = nil) {
        self.tag = tag
        self.title = title
        self.image = image
        self.titleColor = titleColor
    }
}

struct FixedPopUpPicker<Tag: Hashable>: NSViewRepresentable {
    let options: [PopUpOption<Tag>]
    @Binding var selection: Tag

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let signature = options.map { option in
            "\(option.tag)|\(option.title)|\(option.image.map { ObjectIdentifier($0).hashValue } ?? 0)|\(option.titleColor != nil)"
        }
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            let menu = NSMenu()
            for option in options {
                let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
                item.image = option.image
                if let color = option.titleColor {
                    item.attributedTitle = NSAttributedString(string: option.title, attributes: [.foregroundColor: color, .font: NSFont.menuFont(ofSize: 0)])
                }
                menu.addItem(item)
            }
            button.menu = menu
        }
        button.selectItem(at: options.firstIndex { $0.tag == selection } ?? -1)
        button.isEnabled = context.environment.isEnabled
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        if let width = proposal.width, width.isFinite { return CGSize(width: width, height: intrinsic.height) }
        return intrinsic
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FixedPopUpPicker
        var signature: [String] = []

        init(_ parent: FixedPopUpPicker) { self.parent = parent }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].tag
        }
    }
}

// MARK: - 字段选择器（带图标）

struct FieldPicker: View {
    let fields: [ConditionField]
    @Binding var selection: String
    let customName: String?
    let iconProvider: (String) -> NSImage?

    var body: some View {
        FixedPopUpPicker(options: popupOptions, selection: $selection)
    }

    private var popupOptions: [PopUpOption<String>] {
        var options: [PopUpOption<String>] = [PopUpOption("", "")]
        options += fields.map { field in
            PopUpOption(field.name, field.displayName, image: iconProvider(field.displayName.components(separatedBy: " / ").first ?? field.displayName))
        }
        if let customName { options.append(PopUpOption(customName, String(localized: "\(customName) (自定义)"))) }
        return options
    }
}

struct IdOption: Identifiable {
    let id: Int64
    let label: String
    let index: Int
}

/// spellId / itemId 值选择器；值不在列表中时显示「（不存在）」并标红。
struct IdPicker: View {
    let options: [IdOption]
    @Binding var selection: String
    let missingFormat: String
    let iconProvider: (Int64) -> NSImage?

    var body: some View {
        FixedPopUpPicker(options: popupOptions, selection: $selection)
    }

    private var popupOptions: [PopUpOption<String>] {
        var popup = options.map { PopUpOption(String($0.id), $0.label, image: iconProvider($0.id)) }
        if !options.contains(where: { String($0.id) == selection.trimmed() }) {
            popup.append(PopUpOption(selection, String(format: missingFormat, selection), titleColor: .systemRed))
        }
        return popup
    }
}
