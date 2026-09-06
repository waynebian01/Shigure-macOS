import SwiftUI
import ShigureCore

/// 菜单栏图标下拉菜单：状态、开关、打开主窗口、退出。
struct StatusMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = model.snapshot
        Text(statusLine).font(.headline)
        if let className = s.className {
            Text("\(className) / \(s.specName ?? "-")" + (s.moduleName.map { " · \($0)" } ?? ""))
        }
        Text(s.currentStep).foregroundStyle(.secondary)
        Divider()
        Button(s.enabled ? "关闭逻辑" : "开启逻辑") { model.toggleEnabled() }
            .disabled(!model.isRunning)
        Button(model.isRunning ? "停止运行" : "启动运行") {
            if model.isRunning { model.stopRuntime() } else { model.startRuntime() }
        }
        Divider()
        Button("打开 Shigure 主窗口") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出 Shigure") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if !model.isRunning { return "Shigure - 未运行" }
        return model.snapshot.enabled ? "Shigure - 已开启" : "Shigure - 已关闭"
    }
}
