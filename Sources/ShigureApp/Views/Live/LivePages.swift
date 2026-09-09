import SwiftUI
import ShigureCore

// MARK: - 状态页

struct StatusRow: Identifiable, Hashable {
    let id: String
    let category: String
    let unit: String
    let name: String
    let spellId: String
    let type: String
    let value: String
    let iconId: Int64
    let isItem: Bool
}

struct StatusPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.snapshot
        if s.state == nil {
            ContentUnavailableView {
                Label(model.isRunning ? "等待游戏状态" : "未运行", systemImage: "waveform.path.ecg")
            } description: {
                Text(model.isRunning ? "已连接游戏，等待首帧状态数据。" : "从工具栏启动运行会话后，这里会显示实时状态。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                StatusSection(title: "状态", rows: stateRows(s), columns: [.category, .name, .value])
                StatusSection(title: "光环", rows: auraRows(s), columns: [.category, .unit, .name, .spellId, .value])
                StatusSection(title: "技能", rows: spellRows(s), columns: [.category, .name, .spellId, .value])
                StatusSection(title: "动态单位", rows: dynamicRows(s), columns: [.category, .name, .value])
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func stateRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        var rows: [StatusRow] = []
        if let module = s.moduleName {
            rows.append(StatusRow(id: "匹配模块", category: "模块", unit: "", name: "匹配模块", spellId: "", type: "", value: module, iconId: 0, isItem: false))
        }
        for key in state.valueOrder where !state.itemIds.keys.contains(key) {
            let value = state.values[key] ?? nil
            rows.append(StatusRow(id: key, category: ClassStateCatalog.classifyField(key), unit: "", name: key, spellId: "", type: "", value: value?.displayText ?? "-", iconId: 0, isItem: false))
        }
        return rows
    }

    private func auraRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        return state.auraOrder.compactMap { key in
            guard let parsed = SpellFieldKey.parseAura("auras." + key) else { return nil }
            let name = model.iconCatalog.spellName(parsed.spellId) ?? String(localized: "未知法术")
            let type = String(localized: parsed.metric == SpellFieldKey.auraApplications ? "层数" : "时间")
            return StatusRow(id: key, category: type, unit: parsed.scope, name: name, spellId: String(parsed.spellId), type: type,
                             value: (state.auras[key] ?? nil)?.displayText ?? "-", iconId: parsed.spellId, isItem: false)
        }
    }

    private func spellRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        var rows: [StatusRow] = []
        for key in state.spellOrder {
            guard let parsed = SpellFieldKey.parseSpell("spells." + key) else { continue }
            let name = model.iconCatalog.spellName(parsed.spellId) ?? String(localized: "未知法术")
            let type: String
            if let display = state.spellDisplayTypes[key] {
                type = display
            } else {
                switch parsed.metric {
                case SpellFieldKey.spellChargeCooldown: type = String(localized: "充能")
                case SpellFieldKey.spellCount: type = String(localized: "充能层数")
                default: type = String(localized: "冷却")
                }
            }
            rows.append(StatusRow(id: key, category: type, unit: "", name: name, spellId: String(parsed.spellId), type: type,
                                  value: (state.spells[key] ?? nil)?.displayText ?? "-", iconId: parsed.spellId, isItem: false))
        }
        for (field, itemId) in state.itemIds.sorted(by: { $0.key < $1.key }) {
            rows.append(StatusRow(id: "item:\(field)", category: "物品", unit: "", name: field, spellId: String(itemId), type: String(localized: "冷却"),
                                  value: (state.values[field] ?? nil)?.displayText ?? "-", iconId: itemId, isItem: true))
        }
        return rows
    }

    private func dynamicRows(_ s: RenderSnapshot) -> [StatusRow] {
        s.dynamicValues.map {
            let category = String(localized: $0.kind == "单位" ? "动态单位" : "动态数值")
            return StatusRow(id: $0.id, category: category, unit: "", name: $0.name, spellId: "", type: $0.kind, value: $0.value, iconId: 0, isItem: false)
        }
    }
}

enum StatusColumn { case category, unit, name, spellId, type, value }

struct StatusSection: View {
    @Environment(AppModel.self) private var model
    let title: LocalizedStringResource
    let rows: [StatusRow]
    let columns: [StatusColumn]

    var body: some View {
        Section {
            if rows.isEmpty {
                Text("暂无数据").foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    LabeledContent {
                        Text(row.value)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    } label: {
                        HStack(spacing: 8) {
                            rowIcon(row)
                            if columns.contains(.category) {
                                Text(localizedReferenceText(row.category))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 72, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(localizedReferenceText(row.name))
                                if let detail = detailText(row) {
                                    Text(detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(rows.count) 项").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func rowIcon(_ row: StatusRow) -> some View {
        if row.iconId > 0, let image = model.iconCatalog.image(id: row.iconId, isItem: row.isItem) {
            Image(nsImage: image).resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Circle().fill(CategoryAccent.color(row.category)).frame(width: 8, height: 8)
                .frame(width: 20, height: 20)
        }
    }

    private func detailText(_ row: StatusRow) -> String? {
        var parts: [String] = []
        if columns.contains(.unit), !row.unit.isEmpty { parts.append(localizedReferenceText(row.unit)) }
        if columns.contains(.type), !row.type.isEmpty { parts.append(localizedReferenceText(row.type)) }
        if columns.contains(.spellId), !row.spellId.isEmpty { parts.append("ID \(row.spellId)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum CategoryAccent {
    static func color(_ category: String) -> Color {
        switch category {
        case "配置开关": return Color(red: 0xB0 / 255, green: 0x94 / 255, blue: 0xFF / 255)
        case "焦点": return Color(red: 0x78 / 255, green: 0xA8 / 255, blue: 0xFF / 255)
        case "鼠标": return Color(red: 0xF0 / 255, green: 0x8C / 255, blue: 0xC8 / 255)
        case "宠物": return Color(red: 0x8C / 255, green: 0xDC / 255, blue: 0x78 / 255)
        case "物品": return Color(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0x5A / 255)
        case "模块": return .accentColor
        case "特殊": return .yellow
        case "能量": return .cyan
        case "目标": return .red
        default:
            if category.hasPrefix("首领") { return Color(red: 0xFF / 255, green: 0x9E / 255, blue: 0x60 / 255) }
            return .secondary
        }
    }
}

// MARK: - 队伍页

struct PartyPage: View {
    @Environment(AppModel.self) private var model

    struct Row: Identifiable { let id: Int; let unit: String; let summary: String }

    var body: some View {
        GeometryReader { geo in
            let unitWidth = Swift.max(60, geo.size.width * 0.25)
            Table(rows) {
                TableColumn("单位", value: \.unit).width(min: 60, ideal: unitWidth, max: unitWidth)
                TableColumn("摘要", value: \.summary)
            }
        }
        .padding(12)
    }

    private var rows: [Row] {
        guard let state = model.snapshot.state else { return [Row(id: 0, unit: String(localized: "队伍"), summary: String(localized: "无队伍数据"))] }
        let count = state.getInt("队伍人数")
        guard count > 0 else { return [Row(id: 0, unit: String(localized: "队伍"), summary: String(localized: "无队伍数据"))] }
        return (1...min(count, 30)).map { i in
            guard let member = state.group[String(i)] else { return Row(id: i, unit: "Unit \(i)", summary: "-") }
            let summary = member.keys.sorted().map { key -> String in
                let name: String
                if let parsed = SpellFieldKey.parseAuraMember(key) {
                    name = "\(model.iconCatalog.spellName(parsed.spellId) ?? String(parsed.spellId)) \(parsed.metric == SpellFieldKey.auraApplications ? String(localized: "层数") : "")".trimmed()
                } else {
                    name = key
                }
                return "\(localizedReferenceText(name)): \((member[key] ?? nil)?.displayText ?? "-")"
            }.joined(separator: "  ")
            return Row(id: i, unit: "Unit \(i)", summary: summary)
        }
    }
}

// MARK: - 逻辑页

struct LogicPage: View {
    @Environment(AppModel.self) private var model

    struct Row: Identifiable { let id: String; let value: String }

    var body: some View {
        let info = model.snapshot.unitInfo
        let rows = info.keys.sorted().map { Row(id: $0, value: info[$0]?.displayText ?? "-") }
        GeometryReader { geo in
            let nameWidth = Swift.max(100, geo.size.width * 0.25)
            Table(rows.isEmpty ? [Row(id: String(localized: "逻辑信息"), value: String(localized: "无推荐目标"))] : rows) {
                TableColumn("名称") { Text(localizedReferenceText($0.id)) }.width(min: 100, ideal: nameWidth, max: nameWidth)
                TableColumn("值", value: \.value)
            }
        }
        .padding(12)
    }
}

// MARK: - 日志页

struct LogPage: View {
    @Environment(AppModel.self) private var model
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button("复制全部") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logText, forType: .string)
                }
                Button("清空显示", role: .destructive) { model.clearLog() }
                Button("在 Finder 中显示日志文件") { model.revealInFinder(model.paths.logDirectory) }
                Spacer()
                Toggle("自动滚动", isOn: $autoScroll).toggleStyle(.checkbox)
            }
            ScrollViewReader { proxy in
                List(model.logEntries) { entry in
                    Text(entry.formatted)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .id(entry.id)
                }
                .onChange(of: model.logEntries.last?.id) { _, id in
                    if autoScroll, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .padding(12)
    }
}
