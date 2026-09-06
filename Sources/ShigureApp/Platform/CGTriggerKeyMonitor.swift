import AppKit
import CoreGraphics
import ShigureCore

/// 触发键状态（对应 C# GetAsyncKeyState 轮询）。
/// - `isDown`：CGEventSource.keyState / buttonState（无需权限）；
/// - `wasPressed`：可选的被动事件监听（listen-only event tap）在两次采样之间锁存短促点击；
///   需要「输入监控」权限，拿不到时仅靠轮询。
final class CGTriggerKeyMonitor: TriggerKeyState, @unchecked Sendable {
    private let lock = NSLock()
    private var latchedKey: TriggerKeyCode?
    private var latched = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?

    func resolve(keyName: String) -> TriggerKeyCode? {
        let name = keyName.trimmed()
        if let button = MacKeyCodes.mouseButton(for: name) {
            return TriggerKeyCode(kind: .mouseButton(button), name: name.uppercased())
        }
        if MacKeyCodes.isUnsupportedToggleKey(name) { return nil }
        if let code = MacKeyCodes.keyCode(for: name) {
            return TriggerKeyCode(kind: .keyboard(code), name: name.count == 1 ? name : name.uppercased())
        }
        return nil
    }

    func read(_ key: TriggerKeyCode) -> TriggerKeySample {
        let down: Bool
        switch key.kind {
        case .keyboard(let code):
            down = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        case .mouseButton(let button):
            down = CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32(button)) ?? .center)
        }
        let wasPressed: Bool = lock.withLock {
            if latchedKey != key {
                latchedKey = key
                latched = false
                return false
            }
            let value = latched
            latched = false
            return value
        }
        return TriggerKeySample(isDown: down, wasPressed: wasPressed)
    }

    /// 安装被动监听（有「输入监控」权限时生效）。失败时静默回退到纯轮询。
    func startLatchIfPossible() {
        guard lock.withLock({ tap == nil }) else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CGTriggerKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }, userInfo: info) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lock.withLock {
            self.tap = tap
            self.runLoopSource = source
        }
        let thread = Thread { [source] in
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "shigure.trigger-latch"
        thread.qualityOfService = .userInteractive
        thread.start()
        lock.withLock { self.thread = thread }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        lock.withLock {
            guard let key = latchedKey else { return }
            switch (type, key.kind) {
            case (.keyDown, .keyboard(let code)):
                if event.getIntegerValueField(.keyboardEventKeycode) == Int64(code) { latched = true }
            case (.otherMouseDown, .mouseButton(let button)):
                if event.getIntegerValueField(.mouseEventButtonNumber) == Int64(button) { latched = true }
            default:
                break
            }
        }
    }
}
