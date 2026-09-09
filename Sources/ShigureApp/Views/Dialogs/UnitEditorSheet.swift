import SwiftUI
import ShigureCore

/// 动态单位 / 数量编辑（对应 C# UnitEditorForm）。
struct UnitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ModuleEditorStore
    let target: UnitEditorTarget

    enum Category: String, CaseIterable { case unit = "单位 (可作目标)", count = "数量 (仅条件)", value = "数值 (仅条件)" }
    enum AuraFilter: String, CaseIterable { case none = "不筛选光环", anyWith = "带任一光环", anyWithout = "不带任一光环", without = "不带某光环", with = "带某光环", countEquals = "某光环值等于" }
    enum RoleFilter: String, CaseIterable { case none = "不筛选职责", include = "包含某职责", exclude = "不含某职责" }

    struct UnitSelector: Hashable { let kind: UnitSelectorKind; let title: String }
    static let unitSelectors: [UnitSelector] = [
        .init(kind: .lowestHealth, title: "生命值最低"), .init(kind: .highestHealingAbsorb, title: "治疗吸收最高"),
        .init(kind: .unitWithRole, title: "按职责"), .init(kind: .unitWithRoleWithoutAura, title: "按职责且不带某光环"),
        .init(kind: .unitWithAura, title: "带某光环(持续最久)"), .init(kind: .unitWithAuraShortest, title: "带某光环(持续最短)"),
        .init(kind: .unitWithDispelType, title: "带某驱散类型")
    ]
    struct CountSelector: Hashable { let kind: CountKind; let title: String }
    static let countSelectors: [CountSelector] = [
        .init(kind: .unitsBelowHealth, title: "血量 - 低于阈值"), .init(kind: .unitsWithoutAuraBelowHealth, title: "血量 - 低于阈值不带某光环"),
        .init(kind: .unitsWithAuraBelowHealth, title: "血量 - 低于阈值带某光环"), .init(kind: .unitsAboveHealingAbsorb, title: "治疗吸收 - 大于阈值"),
        .init(kind: .unitsWithoutAuraAboveHealingAbsorb, title: "治疗吸收 - 大于阈值不带某光环"), .init(kind: .unitsWithAuraAboveHealingAbsorb, title: "治疗吸收 - 大于阈值带某光环"),
        .init(kind: .unitsWithAura, title: "光环 - 带某光环")
    ]
    /// 数值类别：结果是一个数（与人数无关），仅用于条件。
    static let valueSelectors: [CountSelector] = [
        .init(kind: .averageHealth, title: "平均血量")
    ]
    /// 平均血量只支持 带/不带 单个光环的筛选。
    static let valueAuraFilters: [AuraFilter] = [.none, .with, .without]

    @State private var category: Category = .unit
    @State private var unitKind: UnitSelectorKind = .lowestHealth
    @State private var countKind: CountKind = .unitsBelowHealth
    @State private var valueKind: CountKind = .averageHealth
    @State private var name = ""
    @State private var healthName = ""
    @State private var dynamicThreshold = false
    @State private var threshold = 100
    @State private var thresholdField = ""
    @State private var auraFilter: AuraFilter = .none
    @State private var roleFilter: RoleFilter = .none
    @State private var role = 1
    @State private var reverse = false
    @State private var aura: Int64 = 0
    @State private var auras: Set<Int64> = []
    @State private var auraCount = 1
    @State private var dispelType = 1
    @State private var error: String?
    @State private var originalId: UUID?
    @State private var originalName: String?
    @State private var originalHealthName: String?

    private var auraFields: [ConditionField] { store.support.catalog.groupAuraFields(classId: store.draft.match.classId, specId: store.draft.match.specId) }
    private var thresholdFields: [String] { store.support.thresholdFields(module: store.draft) }

    var body: some View {
        VStack(spacing: 0) {
            Text("编辑单位").font(.title3.bold()).padding(12)
            Divider()
            Form {
                Section {
                    LabeledContent("类别") {
                        FixedPopUpPicker(options: Category.allCases.map { PopUpOption($0, localizedReferenceText($0.rawValue)) }, selection: $category)
                            .frame(width: 240)
                            .disabled(originalId != nil)
                    }
                    if category == .unit {
                        LabeledContent("选择器") {
                            FixedPopUpPicker(options: Self.unitSelectors.map { PopUpOption($0.kind, localizedReferenceText($0.title)) }, selection: $unitKind)
                                .frame(width: 240)
                        }
                    } else if category == .count {
                        LabeledContent("选择器") {
                            FixedPopUpPicker(options: Self.countSelectors.map { PopUpOption($0.kind, localizedReferenceText($0.title)) }, selection: $countKind)
                                .frame(width: 240)
                        }
                    } else {
                        LabeledContent("选择器") {
                            FixedPopUpPicker(options: Self.valueSelectors.map { PopUpOption($0.kind, localizedReferenceText($0.title)) }, selection: $valueKind)
                                .frame(width: 240)
                        }
                    }
                    TextField("名称", text: $name).textFieldStyle(.roundedBorder)
                    if category == .unit, resolvedUnitKind == .lowestHealth {
                        TextField("值名称（可选）", text: $healthName).textFieldStyle(.roundedBorder)
                        Text("把该单位生命值暴露为同名数值条件字段（如 最低血量 < 50）").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("参数") {
                    if showsThreshold {
                        LabeledContent("阈值类型") {
                            FixedPopUpPicker(options: [PopUpOption(false, String(localized: "固定阈值")), PopUpOption(true, String(localized: "动态阈值"))], selection: $dynamicThreshold)
                                .frame(width: 240)
                        }
                        if dynamicThreshold {
                            LabeledContent("动态阈值") {
                                FixedPopUpPicker(options: [PopUpOption("", "")] + thresholdFields.map { PopUpOption($0, $0) }, selection: $thresholdField)
                                    .frame(width: 240)
                            }
                        } else {
                            LabeledContent {
                                HStack(spacing: 4) {
                                    TextField("", value: $threshold, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                        .onChange(of: threshold) { _, value in
                                            threshold = min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
                                        }
                                    Stepper("", value: $threshold, in: thresholdRange).labelsHidden()
                                }
                            } label: {
                                Text(isHealingAbsorb ? String(localized: "治疗吸收阈值 (>)") : String(localized: "血量阈值 (<)"))
                            }
                        }
                    }
                    if category == .unit, unitKind == .lowestHealth || unitKind == .highestHealingAbsorb {
                        LabeledContent("光环筛选") {
                            FixedPopUpPicker(options: AuraFilter.allCases.map { PopUpOption($0, localizedReferenceText($0.rawValue)) }, selection: $auraFilter)
                                .frame(width: 240)
                        }
                    }
                    if category == .unit, unitKind == .lowestHealth {
                        LabeledContent("职责筛选") {
                            FixedPopUpPicker(options: RoleFilter.allCases.map { PopUpOption($0, localizedReferenceText($0.rawValue)) }, selection: $roleFilter)
                                .frame(width: 240)
                        }
                    }
                    if category == .value, valueKind == .averageHealth {
                        LabeledContent("光环筛选") {
                            FixedPopUpPicker(options: Self.valueAuraFilters.map { PopUpOption($0, localizedReferenceText($0.rawValue)) }, selection: $auraFilter)
                                .frame(width: 240)
                        }
                        LabeledContent("职责筛选") {
                            FixedPopUpPicker(options: RoleFilter.allCases.map { PopUpOption($0, localizedReferenceText($0.rawValue)) }, selection: $roleFilter)
                                .frame(width: 240)
                        }
                    }
                    if showsRole {
                        LabeledContent("职责") {
                            FixedPopUpPicker(options: [PopUpOption(1, String(localized: "坦克 (1)")), PopUpOption(2, String(localized: "治疗 (2)")), PopUpOption(3, String(localized: "输出 (3)"))], selection: $role)
                                .frame(width: 240)
                        }
                    }
                    if category == .unit, unitKind == .unitWithRole || unitKind == .unitWithRoleWithoutAura {
                        Toggle("取逆序最后一个匹配单位", isOn: $reverse)
                    }
                    if needsSingleAura {
                        LabeledContent("光环") {
                            FixedPopUpPicker(options: [PopUpOption(Int64(0), "")] + auraFields.map { PopUpOption(auraId($0), $0.displayName) }, selection: $aura)
                                .frame(width: 240)
                        }
                    }
                    if needsAuraList {
                        VStack(alignment: .leading) {
                            Text("光环 (可多选)")
                            ForEach(auraFields) { field in
                                Toggle(field.displayName, isOn: Binding(get: { auras.contains(auraId(field)) }, set: { on in if on { auras.insert(auraId(field)) } else { auras.remove(auraId(field)) } }))
                            }
                        }
                    }
                    if category == .unit, resolvedUnitKind == .lowestHealthWithAuraCount || resolvedUnitKind == .highestHealingAbsorbWithAuraCount {
                        Stepper(value: $auraCount, in: 0...100) { Text("光环值: \(auraCount)") }
                    }
                    if category == .unit, unitKind == .unitWithDispelType {
                        LabeledContent("驱散类型") {
                            FixedPopUpPicker(options: [PopUpOption(1, String(localized: "1: 魔法")), PopUpOption(2, String(localized: "2: 诅咒")), PopUpOption(3, String(localized: "3: 疾病")), PopUpOption(4, String(localized: "4: 中毒"))], selection: $dispelType)
                                .frame(width: 240)
                        }
                    }
                }
                Section {
                    Text("预览: \(previewText)").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确定") { confirm() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear(perform: seed)
    }

    // MARK: 派生

    private func auraId(_ field: ConditionField) -> Int64 {
        field.name.split(separator: ".").compactMap { Int64($0) }.first ?? 0
    }

    private var isHealingAbsorb: Bool { category == .unit ? unitKind == .highestHealingAbsorb : countKind.isHealingAbsorbKind }

    private var thresholdRange: ClosedRange<Int> { (isHealingAbsorb ? 0 : 1)...1000 }

    private var showsThreshold: Bool {
        switch category {
        case .count: return countKind != .unitsWithAura
        case .value: return false
        case .unit: return unitKind == .lowestHealth || unitKind == .highestHealingAbsorb
        }
    }

    private var showsRole: Bool {
        switch category {
        case .count: return false
        case .value: return valueKind == .averageHealth && roleFilter != .none
        case .unit: return unitKind == .unitWithRole || unitKind == .unitWithRoleWithoutAura || (unitKind == .lowestHealth && roleFilter != .none)
        }
    }

    private var resolvedCountKind: CountKind {
        let base = category == .value ? valueKind : countKind
        guard base == .averageHealth else { return base }
        switch auraFilter {
        case .with: return .averageHealthWithAura
        case .without: return .averageHealthWithoutAura
        default: return .averageHealth
        }
    }

    private var resolvedUnitKind: UnitSelectorKind {
        guard unitKind == .lowestHealth || unitKind == .highestHealingAbsorb else { return unitKind }
        let absorb = unitKind == .highestHealingAbsorb
        switch auraFilter {
        case .none: return unitKind
        case .anyWith: return absorb ? .highestHealingAbsorbWithAnyAura : .lowestHealthWithAnyAura
        case .anyWithout: return absorb ? .highestHealingAbsorbWithoutAnyAura : .lowestHealthWithoutAnyAura
        case .without: return absorb ? .highestHealingAbsorbWithoutAura : .lowestHealthWithoutAura
        case .with: return absorb ? .highestHealingAbsorbWithAura : .lowestHealthWithAura
        case .countEquals: return absorb ? .highestHealingAbsorbWithAuraCount : .lowestHealthWithAuraCount
        }
    }

    private var needsAuraList: Bool { category == .unit && resolvedUnitKind.usesAuraList }
    private var needsSingleAura: Bool {
        if category != .unit { return resolvedCountKind.requiresAura }
        return resolvedUnitKind.requiresAura && !resolvedUnitKind.usesAuraList
    }

    private func buildUnit() -> ModuleUnit {
        var unit = ModuleUnit()
        if let originalId { unit.id = originalId }
        unit.name = name.trimmed()
        unit.healthName = (resolvedUnitKind == .lowestHealth && !healthName.isBlank) ? healthName.trimmed() : nil
        unit.kind = resolvedUnitKind
        if resolvedUnitKind.isLowestHealthKind {
            unit.roleFilter = roleFilter == .none ? nil : (roleFilter == .include ? .include : .exclude)
            unit.role = roleFilter == .none ? nil : role
        }
        if unitKind == .unitWithRole || unitKind == .unitWithRoleWithoutAura {
            unit.role = role
            unit.reverse = reverse
        }
        if resolvedUnitKind.usesAuraList { unit.auraSpellIds = auraFields.compactMap { auras.contains(auraId($0)) ? auraId($0) : nil } }
        else if resolvedUnitKind.requiresAura { unit.auraSpellIds = aura > 0 ? [aura] : [] }
        if resolvedUnitKind == .lowestHealthWithAuraCount || resolvedUnitKind == .highestHealingAbsorbWithAuraCount { unit.auraCount = auraCount }
        if unitKind == .unitWithDispelType { unit.dispelType = dispelType }
        if showsThreshold {
            if dynamicThreshold { unit.healthThresholdField = thresholdField.isBlank ? nil : thresholdField } else { unit.healthThreshold = threshold }
        }
        return unit
    }

    private func buildCount() -> ModuleCountField {
        var count = ModuleCountField()
        if let originalId { count.id = originalId }
        count.name = name.trimmed()
        count.kind = resolvedCountKind
        if resolvedCountKind.requiresAura { count.auraSpellId = aura > 0 ? aura : nil }
        if category == .value, valueKind == .averageHealth {
            count.roleFilter = roleFilter == .none ? nil : (roleFilter == .include ? .include : .exclude)
            count.role = roleFilter == .none ? nil : role
        }
        if showsThreshold {
            if dynamicThreshold { count.healthThresholdField = thresholdField.isBlank ? nil : thresholdField } else { count.healthThreshold = threshold }
        }
        return count
    }

    private var previewText: String {
        category == .unit ? UnitSummary.describe(buildUnit(), resolveAuraName: { store.groupAuraName($0) })
                          : UnitSummary.describe(buildCount(), resolveAuraName: { store.groupAuraName($0) })
    }

    private func confirm() {
        let trimmed = name.trimmed()
        let taken = store.support.takenNames(module: store.draft, excluding: [originalName, originalHealthName])
        if let message = store.support.validateName(trimmed, taken: taken) { error = message; return }
        if category == .unit {
            let hn = healthName.trimmed()
            if resolvedUnitKind == .lowestHealth, !hn.isEmpty {
                if hn.caseInsensitiveCompare(trimmed) == .orderedSame { error = String(localized: "值名称不能与名称相同。"); return }
                if let message = store.support.validateName(hn, taken: taken) { error = String(localized: "值名称: \(message)"); return }
            }
            if needsSingleAura, aura <= 0 { error = String(localized: "请选择光环。"); return }
            if needsAuraList, auras.isEmpty { error = String(localized: "请至少勾选一个光环。"); return }
            if showsThreshold, dynamicThreshold, thresholdField.isBlank { error = String(localized: "请选择动态阈值。"); return }
            store.upsertUnit(buildUnit())
        } else {
            if needsSingleAura, aura <= 0 { error = String(localized: "请选择光环。"); return }
            if showsThreshold, dynamicThreshold, thresholdField.isBlank { error = String(localized: "请选择动态阈值。"); return }
            store.upsertCount(buildCount())
        }
        dismiss()
    }

    private func seed() {
        switch target {
        case .unit(let unit):
            category = .unit
            if store.draft.units.contains(where: { $0.id == unit.id }) { originalId = unit.id; originalName = unit.name; originalHealthName = unit.healthName }
            name = unit.name
            healthName = unit.healthName ?? ""
            let kind = unit.kind
            switch kind {
            case .lowestHealth, .lowestHealthWithAnyAura, .lowestHealthWithoutAnyAura, .lowestHealthWithoutAura, .lowestHealthWithAura, .lowestHealthWithAuraCount:
                unitKind = .lowestHealth
            case .highestHealingAbsorb, .highestHealingAbsorbWithAnyAura, .highestHealingAbsorbWithoutAnyAura, .highestHealingAbsorbWithoutAura, .highestHealingAbsorbWithAura, .highestHealingAbsorbWithAuraCount:
                unitKind = .highestHealingAbsorb
            default:
                unitKind = kind
            }
            switch kind {
            case .lowestHealthWithAnyAura, .highestHealingAbsorbWithAnyAura: auraFilter = .anyWith
            case .lowestHealthWithoutAnyAura, .highestHealingAbsorbWithoutAnyAura: auraFilter = .anyWithout
            case .lowestHealthWithoutAura, .highestHealingAbsorbWithoutAura: auraFilter = .without
            case .lowestHealthWithAura, .highestHealingAbsorbWithAura: auraFilter = .with
            case .lowestHealthWithAuraCount, .highestHealingAbsorbWithAuraCount: auraFilter = .countEquals
            default: auraFilter = .none
            }
            if let filter = unit.roleFilter { roleFilter = filter == .include ? .include : .exclude }
            role = unit.role ?? 1
            reverse = unit.reverse
            aura = unit.auraSpellIds?.first ?? 0
            auras = Set(unit.auraSpellIds ?? [])
            auraCount = unit.auraCount ?? 1
            dispelType = unit.dispelType ?? 1
            threshold = unit.healthThreshold ?? (kind.isHealingAbsorbKind ? 0 : 100)
            dynamicThreshold = !(unit.healthThresholdField.isNilOrBlank)
            thresholdField = unit.healthThresholdField ?? ""
        case .count(let count):
            category = count.kind.isAverageHealthKind ? .value : .count
            if store.draft.counts.contains(where: { $0.id == count.id }) { originalId = count.id; originalName = count.name }
            name = count.name
            if count.kind.isAverageHealthKind { valueKind = .averageHealth } else { countKind = count.kind }
            switch count.kind {
            case .averageHealthWithAura: auraFilter = .with
            case .averageHealthWithoutAura: auraFilter = .without
            default: auraFilter = .none
            }
            if let filter = count.roleFilter { roleFilter = filter == .include ? .include : .exclude }
            role = count.role ?? 1
            aura = count.auraSpellId ?? 0
            threshold = count.healthThreshold ?? (count.kind.isHealingAbsorbKind ? 0 : 100)
            dynamicThreshold = !(count.healthThresholdField.isNilOrBlank)
            thresholdField = count.healthThresholdField ?? ""
        }
    }
}
