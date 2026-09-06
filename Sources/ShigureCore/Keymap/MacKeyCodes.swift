import Foundation

/// Windows 键名 ↔ macOS 虚拟键码（kVK_*，固定 ANSI 布局，不查键盘布局）。
/// 修饰符映射：CTRL→Control、ALT→Option、SHIFT→Shift。
public enum MacKeyCodes {
    public enum Modifier: String, Sendable, CaseIterable {
        case ctrl = "CTRL"
        case alt = "ALT"
        case shift = "SHIFT"

        public var keyCode: UInt16 {
            switch self {
            case .ctrl: return 0x3B
            case .alt: return 0x3A
            case .shift: return 0x38
            }
        }
    }

    /// 键名（大写）→ 键码。
    public static let named: [String: UInt16] = [
        "NUMPAD0": 0x52, "NUMPAD1": 0x53, "NUMPAD2": 0x54, "NUMPAD3": 0x55, "NUMPAD4": 0x56,
        "NUMPAD5": 0x57, "NUMPAD6": 0x58, "NUMPAD7": 0x59, "NUMPAD8": 0x5B, "NUMPAD9": 0x5C,
        "NUMPADDECIMAL": 0x41, "NUMPADPLUS": 0x45, "NUMPADMINUS": 0x4E, "NUMPADMULTIPLY": 0x43,
        "NUMPADDIVIDE": 0x4B, "NUMPADENTER": 0x4C,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
        "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
        "F13": 0x69, "F14": 0x6B, "F15": 0x71, "F16": 0x6A, "F17": 0x40, "F18": 0x4F, "F19": 0x50,
        "INSERT": 0x72, "DELETE": 0x75, "HOME": 0x73, "END": 0x77, "PAGEUP": 0x74, "PAGEDOWN": 0x79,
        "LEFT": 0x7B, "RIGHT": 0x7C, "DOWN": 0x7D, "UP": 0x7E,
        "SPACE": 0x31, "TAB": 0x30, "ENTER": 0x24, "RETURN": 0x24, "ESCAPE": 0x35, "BACKSPACE": 0x33,
        "CAPSLOCK": 0x39,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        "A": 0x00, "B": 0x0B, "C": 0x08, "D": 0x02, "E": 0x0E, "F": 0x03, "G": 0x05, "H": 0x04, "I": 0x22, "J": 0x26,
        "K": 0x28, "L": 0x25, "M": 0x2E, "N": 0x2D, "O": 0x1F, "P": 0x23, "Q": 0x0C, "R": 0x0F, "S": 0x01, "T": 0x11,
        "U": 0x20, "V": 0x09, "W": 0x0D, "X": 0x07, "Y": 0x10, "Z": 0x06,
        ",": 0x2B, ".": 0x2F, "/": 0x2C, ";": 0x29, "'": 0x27, "[": 0x21, "]": 0x1E, "\\": 0x2A, "=": 0x18, "-": 0x1B, "`": 0x32
    ]

    /// 鼠标侧键：XBUTTON1 = 按钮 3，XBUTTON2 = 按钮 4（CGMouseButton 原始值）。
    public static let mouseButtons: [String: Int] = [
        "XBUTTON1": 3, "X1": 3, "MOUSE4": 3,
        "XBUTTON2": 4, "X2": 4, "MOUSE5": 4
    ]

    public static func keyCode(for name: String) -> UInt16? {
        let key = name.trimmed()
        if key.count == 1 { return named[key.uppercased()] ?? named[key] }
        return named[key.uppercased()]
    }

    public static func mouseButton(for name: String) -> Int? {
        mouseButtons[name.trimmed().uppercased()]
    }

    /// 键码 → 键名（用于触发键录制）。
    public static func name(for keyCode: UInt16) -> String? {
        // 优先返回热键池/常用名称
        let preferred = ["NUMPAD0", "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9",
                         "NUMPADDECIMAL", "NUMPADPLUS", "NUMPADMINUS", "NUMPADMULTIPLY", "NUMPADDIVIDE", "NUMPADENTER",
                         "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "F13", "F14", "F15", "F16", "F17", "F18", "F19",
                         "INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN", "LEFT", "RIGHT", "DOWN", "UP",
                         "SPACE", "TAB", "ENTER", "ESCAPE", "BACKSPACE", "CAPSLOCK"]
        for name in preferred where named[name] == keyCode { return name }
        return named.first { $0.value == keyCode }?.key
    }

    public static func mouseButtonName(_ button: Int) -> String? {
        switch button {
        case 3: return "XBUTTON1"
        case 4: return "XBUTTON2"
        default: return nil
        }
    }

    /// 触发键不允许使用 Option（原 ALT）以及其它单独的修饰键。
    public static func isUnsupportedToggleKey(_ name: String) -> Bool {
        let upper = name.trimmed().uppercased()
        return ["ALT", "MENU", "LMENU", "RMENU", "OPTION", "LOPTION", "ROPTION", "SHIFT", "CTRL", "CONTROL", "CMD", "COMMAND", "FN"].contains(upper)
    }

    public static let modifierKeyCodes: Set<UInt16> = [0x38, 0x3C, 0x3B, 0x3E, 0x3A, 0x3D, 0x37, 0x36, 0x3F]
}
