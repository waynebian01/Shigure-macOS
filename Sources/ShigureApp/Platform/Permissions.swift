import AppKit
import ApplicationServices
import CoreGraphics

/// macOS TCC 权限：屏幕录制（截屏）、辅助功能（发送按键）、输入监控（可选，触发键事件监听）。
enum Permissions {
    enum Pane: String {
        case screenRecording = "Privacy_ScreenCapture"
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

    @discardableResult
    static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    static func openSystemSettings(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 重启应用：屏幕录制/输入监控在进程运行中途授权时，采集/监听管线要求重启才生效。
    /// 延迟 0.5s 再 `open -n`，确保旧进程已退出，新实例不会被当作重复激活吞掉。
    @MainActor
    static func relaunchApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
