import SwiftUI
import ShigureCore

// MARK: - 状态页

struct StatusRow: Identifiable, Hashable {
    let id: String
    let category: String
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
        HStack(alignment: .top, spacing: 12) {
            StatusListCard(title: "状态", subtitle: "基础字段与当前模块", rows: stateRows(s), columns: [.category, .name, .value])
            StatusListCard(title: "光环", subtitle: "时间与层数", rows: auraRows(s), columns: [.name, .spellId, .type, .value])
            StatusListCard(title: "技能", subtitle: "冷却、充能与次数", rows: spellRows(s), columns: [.name, .spellId, .type, .value])
            StatusListCard(title: "动态单位", subtitle: "模块运行时计算值", rows: dynamicRows(s), columns: [.type, .name, .value])
        }
        .padding(12)
    }

    private func stateRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        var rows: [StatusRow] = []
        if let module = s.moduleName {
            rows.append(StatusRow(id: "匹配模块", category: "模块", name: "匹配模块", spellId: "", type: "", value: module, iconId: 0, isItem: false))
        }
        for key in state.valueOrder where !state.itemIds.keys.contains(key) {
            let value = state.values[key] ?? nil
            rows.append(StatusRow(id: key, category: ClassStateCatalog.classifyField(key), name: key, spellId: "", type: "", value: value?.displayText ?? "-", iconId: 0, isItem: false))
        }
        return rows
    }

    private func auraRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        return state.auraOrder.compactMap { key in
            guard let parsed = SpellFieldKey.parseAura("auras." + key) else { return nil }
            let name = model.iconCatalog.spellName(parsed.spellId) ?? "未知法术"
            let type = parsed.metric == SpellFieldKey.auraApplications ? "层数" : "时间"
            return StatusRow(id: key, category: parsed.scope, name: "\(name) · \(parsed.scope)", spellId: String(parsed.spellId), type: type,
                             value: (state.auras[key] ?? nil)?.displayText ?? "-", iconId: parsed.spellId, isItem: false)
        }
    }

    private func spellRows(_ s: RenderSnapshot) -> [StatusRow] {
        guard let state = s.state else { return [] }
        var rows: [StatusRow] = []
        for key in state.spellOrder {
            guard let parsed = SpellFieldKey.parseSpell("spells." + key) else { continue }
            let name = model.iconCatalog.spellName(parsed.spellId) ?? "未知法术"
            let type: String
            if let display = state.spellDisplayTypes[key] {
                type = display
            } else {
                switch parsed.metric {
                case SpellFieldKey.spellChargeCooldown: type = "充能"
                case SpellFieldKey.spellCount: type = "层数"
                default: type = "冷却"
                }
            }
            rows.append(StatusRow(id: key, category: "技能", name: name, spellId: String(parsed.spellId), type: type,
                                  value: (state.spells[key] ?? nil)?.displayText ?? "-", iconId: parsed.spellId, isItem: false))
        }
        for (field, itemId) in state.itemIds.sorted(by: { $0.key < $1.key }) {
            rows.append(StatusRow(id: "item:\(field)", category: "物品", name: field, spellId: String(itemId), type: "冷却",
                                  value: (state.values[field] ?? nil)?.displayText ?? "-", iconId: itemId, isItem: true))
        }
        return rows
    }

    private func dynamicRows(_ s: RenderSnapshot) -> [StatusRow] {
        s.dynamicValues.map { StatusRow(id: $0.id, category: $0.kind, name: $0.name, spellId: "", type: $0.kind, value: $0.value, iconId: 0, isItem: false) }
    }
}

enum StatusColumn { case category, name, spellId, type, value }

struct StatusListCard: View {
    @Environment(AppModel.self) private var model
    let title: String
    let subtitle: String
    let rows: [StatusRow]
    let columns: [StatusColumn]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Text("\(rows.count) 项").font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                Spacer()
            }
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            Table(rows) {
                TableColumn("#") { row in
                    if row.iconId > 0, let image = model.iconCatalog.image(id: row.iconId, isItem: row.isItem) {
                        Image(nsImage: image).resizable().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Circle().fill(CategoryAccent.color(row.category)).frame(width: 8, height: 8)
                    }
                }.width(28)
                if columns.contains(.category) { TableColumn("分类", value: \.category).width(min: 50, ideal: 60) }
                if columns.contains(.type) { TableColumn("类型", value: \.type).width(min: 44, ideal: 56) }
                TableColumn("名称", value: \.name)
                if columns.contains(.spellId) { TableColumn("ID", value: \.spellId).width(min: 60, ideal: 76) }
                TableColumn("值", value: \.value).width(min: 44, ideal: 70)
            }
            .overlay {
                if rows.isEmpty {
                    Text(model.isRunning ? "等待游戏状态" : "未运行").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
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
        Table(rows) {
            TableColumn("单位", value: \.unit).width(min: 60, ideal: 80)
            TableColumn("摘要", value: \.summary)
        }
        .padding(12)
    }

    private var rows: [Row] {
        guard let state = model.snapshot.state else { return [Row(id: 0, unit: "队伍", summary: "无队伍数据")] }
        let count = state.getInt("队伍人数")
        guard count > 0 else { return [Row(id: 0, unit: "队伍", summary: "无队伍数据")] }
        return (1...min(count, 30)).map { i in
            guard let member = state.group[String(i)] else { return Row(id: i, unit: "Unit \(i)", summary: "-") }
            let summary = member.keys.sorted().map { key -> String in
                let name: String
                if let parsed = SpellFieldKey.parseAuraMember(key) {
                    name = "\(model.iconCatalog.spellName(parsed.spellId) ?? String(parsed.spellId)) \(parsed.metric == SpellFieldKey.auraApplications ? "层数" : "")".trimmed()
                } else {
                    name = key
                }
                return "\(name): \((member[key] ?? nil)?.displayText ?? "-")"
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
        Table(rows.isEmpty ? [Row(id: "逻辑信息", value: "无推荐目标")] : rows) {
            TableColumn("名称", value: \.id).width(min: 100, ideal: 160)
            TableColumn("值", value: \.value)
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
