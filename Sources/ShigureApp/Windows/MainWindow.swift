import SwiftUI
import ShigureCore

enum AppPage: String, CaseIterable, Identifiable {
    case general, config, macros, modules, status, party, logic, logs, bosses, fields, about

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .general: return "通用"
        case .config: return "配置"
        case .macros: return "宏"
        case .modules: return "模块"
        case .status: return "状态"
        case .party: return "队伍"
        case .logic: return "逻辑"
        case .logs: return "日志"
        case .bosses: return "首领"
        case .fields: return "字段"
        case .about: return "关于"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .general: return "运行控制、配置同步、数据包与模块选择"
        case .config: return "编辑职业、专精和扫描字段"
        case .macros: return "维护职业动态宏、静态宏与特殊宏"
        case .modules: return "创建、匹配并维护运行模块"
        case .status: return "实时状态、光环、技能与动态值"
        case .party: return "当前队伍单位与扫描字段摘要"
        case .logic: return "运行时推荐目标与调试值"
        case .logs: return "运行、模块匹配与施放记录"
        case .bosses: return "副本首领的序号、名称与扫描编号"
        case .fields: return "模块条件可用的状态字段参考"
        case .about: return "应用信息、免责声明、许可证与来源"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .config: return "slider.horizontal.3"
        case .macros: return "command"
        case .modules: return "square.stack.3d.up"
        case .status: return "waveform.path.ecg"
        case .party: return "person.3"
        case .logic: return "brain"
        case .logs: return "doc.text"
        case .bosses: return "crown"
        case .fields: return "list.bullet.rectangle"
        case .about: return "info.circle"
        }
    }

    static let groups: [(title: LocalizedStringResource, pages: [AppPage])] = [
        ("常用", [.general]),
        ("编辑", [.config, .macros, .modules]),
        ("监控", [.status, .party, .logic, .logs]),
        ("说明", [.bosses, .fields]),
        ("系统", [.about])
    ]
}

struct MainWindow: View {
    @Environment(AppModel.self) private var model

    /// 必须由我们自己持有：交给 SwiftUI 的 `.automatic` 时，窗口一窄它就把侧栏收起来，
    /// 并把这个状态存进窗口恢复信息里 —— 之后再怎么拉宽、重启都回不来，
    /// 只剩 ⌃⌘S 一条不显眼的出路。用 @State 固定为每次启动都展开。
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $model.selectedPage) {
                ForEach(AppPage.groups, id: \.pages.first) { group in
                    Section { 
                        ForEach(group.pages) { page in
                            Label { Text(page.title) } icon: { Image(systemName: page.symbol) }.tag(page)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                RuntimeStatusFooter()
            }
            .navigationSplitViewColumnWidth(min: Layout.sidebarMin, ideal: Layout.sidebarIdeal, max: Layout.sidebarMax)
        } detail: {
            VStack(spacing: 0) {
                if !model.missingPermissions.isEmpty {
                    PermissionBanner()
                    Divider()
                }
                detail
            }
            .navigationTitle(Text(model.selectedPage.title))
            .navigationSubtitle(Text(model.selectedPage.subtitle))
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                RuntimeToolbar()
            }
        }
        .sheet(isPresented: Binding(
            get: { model.isPermissionWizardPresented },
            // 关闭必须经过 dismissPermissionWizard()，Esc/交互式关闭才会置本会话抑制标志。
            set: { presented in
                if presented { model.presentPermissionWizard() } else { model.dismissPermissionWizard() }
            }
        )) {
            PermissionWizardSheet()
        }
        .task { model.presentPermissionWizardIfNeeded() }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedPage {
        case .general: GeneralPage()
        case .config: ConfigEditorPage()
        case .macros: MacroEditorPage()
        case .modules: ModuleEditorPage()
        case .status: StatusPage()
        case .party: PartyPage()
        case .logic: LogicPage()
        case .logs: LogPage()
        case .bosses: BossNumbersPage()
        case .fields: CommonFieldsPage()
        case .about: AboutPage()
        }
    }
}

/// 工具栏：开关 / 启停。
struct RuntimeToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let enabled = model.snapshot.enabled
        Button {
            model.toggleEnabled()
        } label: {
            Label(enabled ? "关闭逻辑" : "开启逻辑", systemImage: enabled ? "stop.fill" : "play.fill")
        }
        .disabled(!model.isRunning)
        .help(enabled ? "关闭逻辑（⇧⌘E）" : "开启逻辑（⇧⌘E）")
        .tint(enabled ? .red : .green)

        Button {
            if model.isRunning { model.stopRuntime() } else { model.startRuntime() }
        } label: {
            Label(model.isRunning ? "停止运行" : "启动运行", systemImage: model.isRunning ? "power.circle.fill" : "power.circle")
        }
        .help(model.isRunning ? "停止运行会话" : "启动运行会话")
    }
}

/// 侧栏底部：职业色圆点 + 当前步骤。
struct RuntimeStatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(ClassColors.color(for: s.classId)).frame(width: 10, height: 10)
                Text(s.className.map { "\($0) / \(s.specName ?? "-")" } ?? String(localized: model.isRunning ? "等待游戏状态" : "未运行"))
                    .font(.callout).lineLimit(1)
            }
            Text(localizedReferenceText(s.currentStep)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let target = model.gameTarget {
                Text("游戏 pid \(target.pid)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}

struct PermissionBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("缺少权限：\(model.missingPermissions.joined(separator: "、"))。读取游戏画面需要「屏幕录制」，发送按键需要「辅助功能」。")
                .font(.callout)
            Spacer()
            Button("打开权限向导…") { model.presentPermissionWizard() }
            Button("重新检查") { model.refreshPermissions() }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }
}

/// WoW 职业颜色（与 Windows 版一致）。
enum ClassColors {
    static func color(for classId: Int?) -> Color {
        switch classId {
        case 1: return Color(red: 0xC7 / 255, green: 0x9C / 255, blue: 0x6E / 255)
        case 2: return Color(red: 0xF5 / 255, green: 0x8C / 255, blue: 0xBA / 255)
        case 3: return Color(red: 0xAB / 255, green: 0xD4 / 255, blue: 0x73 / 255)
        case 4: return Color(red: 0xFF / 255, green: 0xF5 / 255, blue: 0x69 / 255)
        case 5: return Color.white
        case 6: return Color(red: 0xC4 / 255, green: 0x1F / 255, blue: 0x3B / 255)
        case 7: return Color(red: 0x00 / 255, green: 0x70 / 255, blue: 0xDE / 255)
        case 8: return Color(red: 0x69 / 255, green: 0xCC / 255, blue: 0xF0 / 255)
        case 9: return Color(red: 0x94 / 255, green: 0x82 / 255, blue: 0xC9 / 255)
        case 10: return Color(red: 0x00 / 255, green: 0xFF / 255, blue: 0x96 / 255)
        case 11: return Color(red: 0xFF / 255, green: 0x7D / 255, blue: 0x0A / 255)
        case 12: return Color(red: 0xA3 / 255, green: 0x30 / 255, blue: 0xC9 / 255)
        case 13: return Color(red: 0x33 / 255, green: 0x93 / 255, blue: 0x7F / 255)
        default: return Color.secondary
        }
    }
}
