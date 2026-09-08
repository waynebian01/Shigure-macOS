import SwiftUI

/// 首次启动权限向导：欢迎 → 屏幕录制 → 辅助功能 → 输入监控（可选）→ 完成。
/// 呈现状态由 `AppModel.isPermissionWizardPresented` 驱动；关闭统一走 `dismissPermissionWizard()`，
/// 保证本会话内不再自动打扰。权限状态靠应用激活时的 `refreshPermissions()` 自动变绿。
struct PermissionWizardSheet: View {
    @Environment(AppModel.self) private var model
    @State private var step: WizardStep = .welcome

    enum WizardStep: Int, CaseIterable {
        case welcome, screenRecording, accessibility, inputMonitoring, done
    }

    var body: some View {
        VStack(spacing: 0) {
            WizardStepIndicator(current: step)
                .padding(.top, 20)
                .padding(.bottom, 8)
            Group {
                switch step {
                case .welcome: welcomeStep
                case .screenRecording: screenRecordingStep
                case .accessibility: accessibilityStep
                case .inputMonitoring: inputMonitoringStep
                case .done: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 36)
            Divider()
            footer.padding(12)
        }
        .frame(width: 560, height: 480)
        .onAppear { step = initialStep }
    }

    /// 从第一个未满足的步骤开始：全新用户看到欢迎页，半路授权过的直接跳到缺的那步。
    private var initialStep: WizardStep {
        if !model.hasScreenRecording && !model.hasAccessibility { return .welcome }
        if !model.hasScreenRecording { return .screenRecording }
        if !model.hasAccessibility { return .accessibility }
        return .done
    }

    // MARK: 步骤内容

    private var welcomeStep: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("欢迎使用 Shigure").font(.title.bold())
            Text("Shigure 需要读取游戏画面并向游戏发送按键才能工作。接下来的几步会引导你在系统设置中授予所需权限，全程约一分钟。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 6) {
                Label("屏幕录制 — 读取游戏窗口像素（必需）", systemImage: "rectangle.dashed.badge.record")
                Label("辅助功能 — 向游戏发送按键（必需）", systemImage: "accessibility")
                Label("输入监控 — 捕获触发键点击（可选）", systemImage: "keyboard")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var screenRecordingStep: some View {
        WizardPermissionStep(
            symbol: "rectangle.dashed.badge.record",
            title: String(localized: "屏幕录制"),
            isOptional: false,
            detail: String(localized: "Shigure 通过截取游戏窗口像素来读取插件渲染的状态点阵。画面只在本机内存中解析，不录制、不保存、不上传任何内容。"),
            granted: model.hasScreenRecording,
            needsRestart: model.screenRecordingNeedsRestart,
            requestTitle: String(localized: "授权屏幕录制"),
            request: { Permissions.requestScreenRecording() },
            openSettings: { Permissions.openSystemSettings(.screenRecording) },
            recheck: { model.refreshPermissions() }
        )
    }

    private var accessibilityStep: some View {
        WizardPermissionStep(
            symbol: "accessibility",
            title: String(localized: "辅助功能"),
            isOptional: false,
            detail: String(localized: "Shigure 通过系统事件向游戏进程发送键盘按键。授权后立即生效，无需重启。"),
            granted: model.hasAccessibility,
            needsRestart: false,
            requestTitle: String(localized: "授权辅助功能"),
            request: { Permissions.requestAccessibility() },
            openSettings: { Permissions.openSystemSettings(.accessibility) },
            recheck: { model.refreshPermissions() }
        )
    }

    private var inputMonitoringStep: some View {
        WizardPermissionStep(
            symbol: "keyboard",
            title: String(localized: "输入监控"),
            isOptional: true,
            detail: String(localized: "仅用于捕获短促的触发键点击（例如鼠标侧键）。不授权也能使用核心功能，可以放心跳过。"),
            granted: model.hasInputMonitoring,
            needsRestart: model.inputMonitoringNeedsRestart,
            requestTitle: String(localized: "授权输入监控"),
            request: { Permissions.requestInputMonitoring() },
            openSettings: { Permissions.openSystemSettings(.inputMonitoring) },
            recheck: { model.refreshPermissions() }
        )
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            Image(systemName: needsRestart ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(needsRestart ? .orange : .green)
            Text(needsRestart ? "还差最后一步" : "设置完成").font(.title.bold())
            VStack(alignment: .leading, spacing: 8) {
                WizardSummaryRow(title: String(localized: "屏幕录制"), granted: model.hasScreenRecording)
                WizardSummaryRow(title: String(localized: "辅助功能"), granted: model.hasAccessibility)
                WizardSummaryRow(title: String(localized: "输入监控（可选）"), granted: model.hasInputMonitoring)
            }
            .padding(.vertical, 4)
            if needsRestart {
                Text("部分权限是在 Shigure 运行中途授予的，需要重启应用才能生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if !model.missingPermissions.isEmpty {
                Text("仍有必需权限未授予：\(model.missingPermissions.joined(separator: "、"))。可以稍后在「通用」页或主窗口横幅中继续设置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("一切就绪，开始使用吧。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var needsRestart: Bool {
        model.screenRecordingNeedsRestart || model.inputMonitoringNeedsRestart
    }

    // MARK: 底部按钮条

    private var footer: some View {
        HStack {
            Button("稍后设置") { model.dismissPermissionWizard() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let previous = WizardStep(rawValue: step.rawValue - 1) {
                Button("上一步") { step = previous }
            }
            switch step {
            case .welcome:
                Button("开始设置") { advance() }
                    .keyboardShortcut(.defaultAction)
            case .screenRecording:
                Button("下一步") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasScreenRecording)
            case .accessibility:
                Button("下一步") { advance() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasAccessibility)
            case .inputMonitoring:
                Button(model.hasInputMonitoring ? "下一步" : "跳过") { advance() }
                    .keyboardShortcut(.defaultAction)
            case .done:
                if needsRestart {
                    Button("稍后重启") { model.dismissPermissionWizard() }
                    Button("重启 Shigure") { Permissions.relaunchApp() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("完成") { model.dismissPermissionWizard() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func advance() {
        guard let next = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }
}

/// 顶部步骤指示器：一排圆点，当前步高亮，走过的步骤淡化。
private struct WizardStepIndicator: View {
    let current: PermissionWizardSheet.WizardStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PermissionWizardSheet.WizardStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s == current ? Color.accentColor : Color.secondary.opacity(s.rawValue < current.rawValue ? 0.5 : 0.2))
                    .frame(width: s == current ? 22 : 8, height: 8)
                    .animation(.snappy(duration: 0.2), value: current)
            }
        }
    }
}

/// 参数化的权限步骤页：说明 + 实时状态 + 授权按钮 + 系统设置直达。
private struct WizardPermissionStep: View {
    let symbol: String
    let title: String
    let isOptional: Bool
    let detail: String
    let granted: Bool
    let needsRestart: Bool
    let requestTitle: String
    let request: () -> Void
    let openSettings: () -> Void
    let recheck: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            HStack(spacing: 6) {
                Text(title).font(.title2.bold())
                Text(isOptional ? "可选" : "必需")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isOptional ? Color.secondary.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(isOptional ? Color.secondary : Color.orange)
            }
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
                Text(granted ? "已授予" : "未授予")
                    .foregroundStyle(.secondary)
                Button("重新检查") { recheck() }
                    .buttonStyle(.link)
                    .font(.callout)
            }
            .font(.callout)

            if granted {
                if needsRestart {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("已授权，但需要重启 Shigure 才能生效。可以先完成剩余步骤，最后一起重启。")
                            .font(.callout)
                        Button("立即重启") { Permissions.relaunchApp() }
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Button(requestTitle) { request() }
                    .controlSize(.large)
                Button("在系统设置中打开…") { openSettings() }
                    .buttonStyle(.link)
                Text("授权后从系统设置切回 Shigure，状态会自动刷新。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 完成页的单行权限状态。
private struct WizardSummaryRow: View {
    let title: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            Text(granted ? "已授予" : "未授予").foregroundStyle(.secondary)
        }
        .font(.callout)
        .frame(width: 260)
    }
}
