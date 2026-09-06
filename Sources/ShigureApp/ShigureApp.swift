import AppKit
import SwiftUI
import ShigureCore

@main
struct ShigureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.sharedModel = model
    }

    var body: some Scene {
        Window("Shigure", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            RuntimeCommands(model: model)
        }

        MenuBarExtra {
            StatusMenu().environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct RuntimeCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("运行") {
            Button(model.snapshot.enabled ? "关闭逻辑" : "开启逻辑") { model.toggleEnabled() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!model.isRunning)
            Divider()
            Button("启动运行") { model.startRuntime() }.disabled(model.isRunning)
            Button("重启运行") { model.restartRuntime(reason: "手动重启") }
            Button("停止运行") { model.stopRuntime() }.disabled(!model.isRunning)
            Divider()
            Button("更新配置") { model.updateConfigFromProject(showFeedback: true) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("刷新模块") { model.reloadModules() }
                .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let color = model.snapshot.enabled ? Color.green : Color.primary
        Image(systemName: model.snapshot.enabled ? "bolt.fill" : "bolt")
            .foregroundStyle(color)
            .accessibilityLabel(model.snapshot.enabled ? "Shigure - 已开启" : "Shigure - 已关闭")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var sharedModel: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppDelegate.sharedModel?.performStartupSequence()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppDelegate.sharedModel?.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
