import AppKit
import CoreGraphics
import ShigureCore

/// 用 CGEvent 向游戏投递按键（对应 C# KeySender.PostMessage）。
/// 顺序与 Windows 版一致：修饰键依次按下 → 主键按下/抬起 → 修饰键逆序抬起；修饰状态同时写在事件 flags 上。
final class CGEventKeyInjector: KeyOutput, @unchecked Sendable {
    private let locator: WorkspaceGameLocator
    private let lock = NSLock()
    private var mode: KeyInjectionMode

    init(locator: WorkspaceGameLocator, mode: KeyInjectionMode) {
        self.locator = locator
        self.mode = mode
    }

    func setMode(_ value: KeyInjectionMode) {
        lock.withLock { mode = value }
    }

    func send(hotkey: String, expectedTarget: GameTarget?) -> KeySendResult {
        let parsed = KeymapCatalog.parseHotkey(hotkey)
        guard let mainKey = parsed.mainKey else { return .failure(String(localized: "无法解析按键“\(hotkey)”")) }
        guard let mainCode = MacKeyCodes.keyCode(for: mainKey) else { return .failure(String(localized: "无法识别主键“\(mainKey)”")) }
        guard let target = locator.currentTarget() else {
            return .failure(String(localized: "未找到目标进程的可见窗口（\(locator.describeConfigured())）"))
        }
        if let expected = expectedTarget, expected.windowID != target.windowID {
            return .failure(String(localized: "目标窗口已切换，等待重新扫描后再发送按键"))
        }
        guard Permissions.accessibility else {
            return .failure(String(localized: "未授予「辅助功能」权限，无法发送按键"))
        }
        let modifiers = parsed.modifiers.compactMap { MacKeyCodes.Modifier(rawValue: $0) }
        let currentMode = lock.withLock { mode }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return .failure(String(localized: "无法创建输入事件源"))
        }

        var flags: CGEventFlags = []
        if Self.isKeypad(mainKey) { flags.insert(.maskNumericPad) }
        // 真实键盘的功能键/导航键事件始终带 fn 标志（方向键还带 numericPad），缺了会被游戏忽略。
        if Self.isFunctionOrNavKey(mainKey) { flags.insert(.maskSecondaryFn) }
        if Self.isArrowKey(mainKey) { flags.insert(.maskNumericPad) }
        var events: [CGEvent] = []
        for modifier in modifiers {
            flags.insert(Self.flag(for: modifier))
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(modifier.keyCode), keyDown: true) else {
                return .failure(String(localized: "无法创建修饰键事件"))
            }
            event.flags = flags
            events.append(event)
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(mainCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(mainCode), keyDown: false) else {
            return .failure(String(localized: "无法创建按键事件"))
        }
        down.flags = flags
        up.flags = flags
        events.append(down)
        events.append(up)
        for modifier in modifiers.reversed() {
            flags.remove(Self.flag(for: modifier))
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(modifier.keyCode), keyDown: false) else {
                return .failure(String(localized: "无法创建修饰键事件"))
            }
            event.flags = flags
            events.append(event)
        }
        for event in events {
            switch currentMode {
            case .process: event.postToPid(target.pid)
            case .system: event.post(tap: .cghidEventTap)
            }
        }
        return .success
    }

    static func flag(for modifier: MacKeyCodes.Modifier) -> CGEventFlags {
        switch modifier {
        case .ctrl: return .maskControl
        case .alt: return .maskAlternate
        case .shift: return .maskShift
        case .cmd: return .maskCommand
        }
    }

    static func isKeypad(_ name: String) -> Bool {
        name.uppercased().hasPrefix("NUMPAD")
    }

    private static let arrowKeys: Set<String> = ["UP", "DOWN", "LEFT", "RIGHT"]
    private static let navKeys: Set<String> = ["INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN"]

    static func isArrowKey(_ name: String) -> Bool {
        arrowKeys.contains(name.uppercased())
    }

    static func isFunctionOrNavKey(_ name: String) -> Bool {
        let upper = name.uppercased()
        if arrowKeys.contains(upper) || navKeys.contains(upper) { return true }
        // F1–F19：F 后跟纯数字
        guard upper.hasPrefix("F"), upper.count >= 2, upper.count <= 3 else { return false }
        return upper.dropFirst().allSatisfy(\.isNumber)
    }
}
