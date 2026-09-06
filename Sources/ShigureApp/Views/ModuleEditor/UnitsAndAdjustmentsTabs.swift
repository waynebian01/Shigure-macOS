import SwiftUI
import ShigureCore

// MARK: - 动态单位 / 数量

struct UnitsTab: View {
    @Bindable var store: ModuleEditorStore
    @State private var editing: UnitEditorTarget?

    enum UnitRowKind: Hashable { case unit(UUID), count(UUID) }

    var body: some View {
        VStack(spacing: 0) {
            if store.draft.units.isEmpty && store.draft.counts.isEmpty {
                ContentUnavailableView("暂无动态单位 / 数量", systemImage: "person.crop.circle.badge.questionmark", description: Text("点击下方「添加」创建"))
            } else {
                List {
                    ForEach(store.draft.units) { unit in
                        let issues = store.issues(for: unit)
                        row(name: unit.healthName.isNilOrBlank ? unit.name : "\(unit.name) / \(unit.healthName!)", kind: "单位",
                            summary: UnitSummary.describe(unit, resolveAuraName: { store.groupAuraName($0) }), issues: issues)
                            .contextMenu {
                                Button("编辑") { editing = .unit(unit) }
                                Button("删除", role: .destructive) { store.deleteUnit(unit) }
                            }
                            .onTapGesture(count: 2) { editing = .unit(unit) }
                    }
                    ForEach(store.draft.counts) { count in
                        let issues = store.issues(for: count)
                        row(name: count.name, kind: "数量", summary: UnitSummary.describe(count, resolveAuraName: { store.groupAuraName($0) }), issues: issues)
                            .contextMenu {
                                Button("编辑") { editing = .count(count) }
                                Button("删除", role: .destructive) { store.deleteCount(count) }
                            }
                            .onTapGesture(count: 2) { editing = .count(count) }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Button { editing = .unit(ModuleUnit()) } label: { Label("添加", systemImage: "plus") }
                Spacer()
                Text("双击编辑；右键删除").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .sheet(item: $editing) { target in
            UnitEditorSheet(store: store, target: target)
        }
    }

    private func row(name: String, kind: String, summary: String, issues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).fontWeight(.medium).frame(width: 200, alignment: .leading).lineLimit(1)
                Text(kind).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(kind == "单位" ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
                Text(summary).foregroundStyle(issues.isEmpty ? Color.primary : Color.red).lineLimit(2)
            }
            if !issues.isEmpty { Text(issues.joined(separator: "；")).font(.caption).foregroundStyle(.red) }
        }
        .contentShape(Rectangle())
        .listRowBackground(issues.isEmpty ? nil : Color.red.opacity(0.08))
    }
}

enum UnitEditorTarget: Identifiable {
    case unit(ModuleUnit)
    case count(ModuleCountField)

    var id: UUID {
        switch self {
        case .unit(let u): return u.id
        case .count(let c): return c.id
        }
    }
}

// MARK: - 动态数值

struct AdjustmentsTab: View {
    @Environment(AppModel.self) private var model
    @Bindable var store: ModuleEditorStore
    @State private var conditionAdjustmentId: UUID?
    @State private var formulaAdjustmentId: UUID?

    static let typeOptions: [ConditionFieldCategory] = [.state, .spell, .aura, .dynamicUnit, .dynamicValue]

    var body: some View {
        VSplitView {
            section(title: "条件动态数值", subtitle: "条件成立时对已有状态、光环、技能或动态字段加减一个整数") {
                List {
                    ForEach(Array(store.draft.valueAdjustments.enumerated()).filter { $0.element.formula.isBlank }, id: \.element.id) { index, adjustment in
                        conditionalRow(index: index, adjustment: adjustment)
                    }
                }
                .listStyle(.inset)
            } footer: {
                Button { var a = ModuleValueAdjustment(); a.delta = 1; store.draft.valueAdjustments.append(a) } label: { Label("添加条件数值", systemImage: "plus") }
            }
            section(title: "公式动态数值", subtitle: "使用字段和算术表达式生成命名数值：+ - * / 括号 int round floor ceil min max") {
                List {
                    ForEach(Array(store.draft.valueAdjustments.enumerated()).filter { !$0.element.formula.isBlank || ($0.element.delta == 0 && $0.element.condition.isEmpty && !$0.element.field.isEmpty && $0.element.formula.isEmpty && isFormulaRow($0.element)) }, id: \.element.id) { index, adjustment in
                        formulaRow(index: index, adjustment: adjustment)
                    }
                }
                .listStyle(.inset)
            } footer: {
                Button { var a = ModuleValueAdjustment(); a.formula = "0"; store.draft.valueAdjustments.append(a); formulaAdjustmentId = a.id } label: { Label("添加公式数值", systemImage: "plus") }
            }
        }
        .sheet(item: Binding(get: { conditionAdjustmentId.map { RuleSheetTarget(id: $0) } }, set: { conditionAdjustmentId = $0?.id })) { target in
            if let index = store.draft.valueAdjustments.firstIndex(where: { $0.id == target.id }) {
                ConditionEditorSheet(
                    context: ConditionEditorContext(store: store, allowSubConditions: false, allowRuleSettings: false),
                    initial: ConditionEditorInitial(condition: store.draft.valueAdjustments[index].condition, subConditions: [], delayMs: nil, logicDelayMs: nil, continueLogic: nil)
                ) { result in
                    store.draft.valueAdjustments[index].condition = result.condition
                }
            }
        }
        .sheet(item: Binding(get: { formulaAdjustmentId.map { RuleSheetTarget(id: $0) } }, set: { formulaAdjustmentId = $0?.id })) { target in
            if let index = store.draft.valueAdjustments.firstIndex(where: { $0.id == target.id }) {
                let current = store.draft.valueAdjustments[index]
                TextEditorSheet(title: "编辑公式", text: current.field.isEmpty ? current.formula : "\(current.field) = \(FormulaEvaluator.normalizeExpression(current.formula))", confirmTitle: "确定", monospaced: true,
                                hint: "可写成「名称 = 表达式」；支持 + - * / 括号、一元正负、int/round/floor/ceil/min/max") { text in
                    if let split = FormulaEvaluator.splitAssignment(text) {
                        store.draft.valueAdjustments[index].field = split.field
                        store.draft.valueAdjustments[index].formula = split.formula
                    } else {
                        store.draft.valueAdjustments[index].formula = FormulaEvaluator.normalizeExpression(text)
                    }
                    store.invalidateValidation()
                }
            }
        }
    }

    private func isFormulaRow(_ a: ModuleValueAdjustment) -> Bool { !a.formula.isBlank }

    private func section<Content: View, Footer: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).padding(.horizontal, 12).padding(.top, 8)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            content()
            HStack { footer(); Spacer() }.padding(8)
        }
        .frame(minHeight: 160)
    }

    private func conditionalRow(index: Int, adjustment: ModuleValueAdjustment) -> some View {
        let issues = store.issues(for: adjustment)
        let fields = store.support.adjustmentFields(module: store.draft)
        let category = resolveCategory(adjustment.field, fields: fields)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { adjustment.enabled }, set: { store.draft.valueAdjustments[index].enabled = $0 })).labelsHidden()
                Picker("", selection: Binding(get: { category }, set: { newCategory in
                    if !fields.contains(where: { $0.name == adjustment.field && $0.category == newCategory }) { store.draft.valueAdjustments[index].field = "" }
                    store.draft.valueAdjustments[index].condition += "" // 触发刷新
                })) {
                    ForEach(Self.typeOptions, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 110)
                Picker("", selection: Binding(get: { adjustment.field }, set: { store.draft.valueAdjustments[index].field = $0; store.invalidateValidation() })) {
                    Text("").tag("")
                    ForEach(fields.filter { $0.category == category }) { Text($0.displayName).tag($0.name) }
                    if !adjustment.field.isEmpty, !fields.contains(where: { $0.name == adjustment.field }) { Text(adjustment.field).tag(adjustment.field) }
                }
                .labelsHidden().frame(width: 240)
                TextField("调整", value: Binding(get: { adjustment.delta }, set: { store.draft.valueAdjustments[index].delta = $0 }), format: .number)
                    .frame(width: 70)
                Button {
                    conditionAdjustmentId = adjustment.id
                } label: {
                    Text(adjustment.condition.isBlank ? "始终" : store.support.humanize(adjustment.condition, spellName: { model.iconCatalog.spellName($0) }, itemName: { model.iconCatalog.itemName($0) }))
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button(role: .destructive) { store.draft.valueAdjustments.remove(at: index) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            if !issues.isEmpty { Text(issues.joined(separator: "；")).font(.caption).foregroundStyle(.red) }
        }
        .listRowBackground(issues.isEmpty ? nil : Color.red.opacity(0.08))
    }

    private func formulaRow(index: Int, adjustment: ModuleValueAdjustment) -> some View {
        let issues = store.issues(for: adjustment)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { adjustment.enabled }, set: { store.draft.valueAdjustments[index].enabled = $0 })).labelsHidden()
                TextField("数值名称", text: Binding(get: { adjustment.field }, set: { store.draft.valueAdjustments[index].field = $0; store.invalidateValidation() }))
                    .frame(width: 180)
                Button { formulaAdjustmentId = adjustment.id } label: {
                    Text(adjustment.formula.isBlank ? "点击编辑公式" : adjustment.formula).font(.system(.body, design: .monospaced)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button(role: .destructive) { store.draft.valueAdjustments.remove(at: index) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            if !issues.isEmpty { Text(issues.joined(separator: "；")).font(.caption).foregroundStyle(.red) }
        }
        .listRowBackground(issues.isEmpty ? nil : Color.red.opacity(0.08))
    }

    private func resolveCategory(_ field: String, fields: [ConditionField]) -> ConditionFieldCategory {
        if let f = fields.first(where: { $0.name == field }) { return f.category }
        if field.hasPrefixIgnoringCase("auras.") { return .aura }
        if field.hasPrefixIgnoringCase("spells.") { return .spell }
        return .dynamicValue
    }
}
