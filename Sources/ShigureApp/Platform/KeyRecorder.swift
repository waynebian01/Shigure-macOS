import AppKit
import ShigureCore

/// 触发键录制：本地事件监视器捕获下一次键盘按键或鼠标侧键。
@MainActor
final class KeyRecorder {
    enum Outcome: Sendable {
        case captured(String)
        case cancelled
        case unsupported(String)
    }

    private var monitor: Any?

    func begin(_ completion: @escaping @MainActor (Outcome) -> Void) {
        end()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            let outcome = Self.interpret(event)
            self.end()
            completion(outcome)
            return nil
        }
    }

    func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    var isRecording: Bool { monitor != nil }

    static func interpret(_ event: NSEvent) -> Outcome {
        switch event.type {
        case .otherMouseDown:
            if let name = MacKeyCodes.mouseButtonName(event.buttonNumber) { return .captured(name) }
            return .unsupported("该鼠标按键暂不支持, 请重试")
        case .keyDown:
            if event.keyCode == 0x35 { return .cancelled } // Escape
            if MacKeyCodes.modifierKeyCodes.contains(event.keyCode) { return .unsupported("触发键不支持单独的修饰键, 请重试") }
            if event.modifierFlags.contains(.option) { return .unsupported("触发键不支持 Option(ALT), 请重试") }
            if event.modifierFlags.contains(.command) { return .unsupported("触发键不支持 Command 组合, 请重试") }
            if let name = MacKeyCodes.name(for: event.keyCode) { return .captured(name) }
            return .unsupported("该按键暂不支持, 请重试")
        default:
            return .unsupported("该按键暂不支持, 请重试")
        }
    }
}
