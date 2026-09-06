import Foundation
import CoreGraphics

public enum SendMode: String, Sendable, CaseIterable, Codable {
    case `switch` = "switch"
    case click = "click"
    case hold = "hold"

    public var displayName: String {
        switch self {
        case .switch: return "开关"
        case .click: return "单击"
        case .hold: return "按住"
        }
    }
}

public struct AppOptions: Sendable, Equatable {
    public var toggleKey: String
    public var mode: SendMode
    public var moduleId: String?
    public var logicInterval: Duration
    public var renderInterval: Duration

    public init(toggleKey: String = "XBUTTON2", mode: SendMode = .switch, moduleId: String? = nil,
                logicMs: Int = 100, renderMs: Int = 100) {
        self.toggleKey = toggleKey
        self.mode = mode
        self.moduleId = moduleId
        self.logicInterval = .milliseconds(max(50, logicMs))
        self.renderInterval = .milliseconds(max(100, renderMs))
    }
}

/// 游戏窗口目标（pid + 窗口 + 屏幕坐标边界）。
public struct GameTarget: Sendable, Equatable, Hashable {
    public let pid: Int32
    public let windowID: UInt32
    /// 窗口内容区域在屏幕坐标系中的位置（点），左上角原点。
    public let bounds: CGRect
    public let bundleURL: URL?

    public init(pid: Int32, windowID: UInt32, bounds: CGRect, bundleURL: URL?) {
        self.pid = pid
        self.windowID = windowID
        self.bounds = bounds
        self.bundleURL = bundleURL
    }

    public static func == (lhs: GameTarget, rhs: GameTarget) -> Bool {
        lhs.pid == rhs.pid && lhs.windowID == rhs.windowID && lhs.bounds == rhs.bounds && lhs.bundleURL == rhs.bundleURL
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(windowID)
        hasher.combine(bounds.origin.x)
        hasher.combine(bounds.origin.y)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
    }
}

/// 一次像素扫描的结果。
public struct ScreenScanResult: Sendable, Equatable {
    /// step (1..510) → 值字节；找不到起始标记时为 nil。
    public var rowData: [Int: Int]?
    /// 段号（1 起）→ 值。
    public var barData: [Int: Int]
    /// 单位 (1..30) → 治疗吸收百分比。
    public var healAbsorbData: [Int: Int]
    public var target: GameTarget?
    public var failureReason: String?

    public init(rowData: [Int: Int]?, barData: [Int: Int] = [:], healAbsorbData: [Int: Int] = [:], target: GameTarget? = nil, failureReason: String? = nil) {
        self.rowData = rowData
        self.barData = barData
        self.healAbsorbData = healAbsorbData
        self.target = target
        self.failureReason = failureReason
    }

    public static func failure(_ reason: String, target: GameTarget? = nil) -> ScreenScanResult {
        ScreenScanResult(rowData: nil, target: target, failureReason: reason)
    }
}

public protocol ScreenScanner: Sendable {
    func scan() async -> ScreenScanResult
}

public struct KeySendResult: Sendable, Equatable {
    public let succeeded: Bool
    public let failureReason: String?
    public static let success = KeySendResult(succeeded: true, failureReason: nil)
    public static func failure(_ reason: String) -> KeySendResult { KeySendResult(succeeded: false, failureReason: reason) }
}

public protocol KeyOutput: Sendable {
    /// expectedTarget 非 nil 时，若当前目标窗口已切换应拒绝发送。
    func send(hotkey: String, expectedTarget: GameTarget?) -> KeySendResult
}

public struct TriggerKeySample: Sendable, Equatable {
    public let isDown: Bool
    /// 自上次采样以来曾按下过（尽力实现，用于捕获短促点击）。
    public let wasPressed: Bool
    public init(isDown: Bool, wasPressed: Bool) {
        self.isDown = isDown
        self.wasPressed = wasPressed
    }
}

public struct TriggerKeyCode: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Hashable { case keyboard(UInt16), mouseButton(Int) }
    public let kind: Kind
    public let name: String
    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
}

public protocol TriggerKeyState: Sendable {
    func resolve(keyName: String) -> TriggerKeyCode?
    func read(_ key: TriggerKeyCode) -> TriggerKeySample
}

public protocol RuntimeLogic: Sendable {
    func evaluate(classId: Int?, specId: Int?, specName: String?, state: inout GameState, runLogic: Bool) -> LogicEvaluation
}

extension LogicRegistry: RuntimeLogic {}

public struct DynamicValueSnapshot: Sendable, Equatable, Identifiable {
    public let kind: String
    public let name: String
    public let value: String
    public var id: String { "\(kind)/\(name)" }
    public init(kind: String, name: String, value: String) {
        self.kind = kind
        self.name = name
        self.value = value
    }
}

public struct RenderSnapshot: Sendable, Equatable {
    public let sessionId: UInt64
    public let enabled: Bool
    public let className: String?
    public let specName: String?
    public let classId: Int?
    public let specId: Int?
    public let moduleName: String?
    public let state: GameState?
    public let currentStep: String
    public let unitInfo: [String: StateValue]
    public let dynamicValues: [DynamicValueSnapshot]
    public let scanFailureReason: String?
    public let target: GameTarget?

    public init(sessionId: UInt64, enabled: Bool, className: String?, specName: String?, classId: Int?, specId: Int?,
                moduleName: String?, state: GameState?, currentStep: String, unitInfo: [String: StateValue],
                dynamicValues: [DynamicValueSnapshot], scanFailureReason: String?, target: GameTarget?) {
        self.sessionId = sessionId
        self.enabled = enabled
        self.className = className
        self.specName = specName
        self.classId = classId
        self.specId = specId
        self.moduleName = moduleName
        self.state = state
        self.currentStep = currentStep
        self.unitInfo = unitInfo
        self.dynamicValues = dynamicValues
        self.scanFailureReason = scanFailureReason
        self.target = target
    }

    public static func idle(sessionId: UInt64 = 0, step: String = "等待启动") -> RenderSnapshot {
        RenderSnapshot(sessionId: sessionId, enabled: false, className: nil, specName: nil, classId: nil, specId: nil,
                       moduleName: nil, state: nil, currentStep: step, unitInfo: [:], dynamicValues: [], scanFailureReason: nil, target: nil)
    }
}
