import Foundation

/// 运行循环（对应 C# ShigureRuntime）。一个实例对应一个会话；由 RuntimeCoordinator 创建与取消。
public actor ShigureRuntime {
    public let options: AppOptions
    public let sessionId: UInt64
    private let scanner: any ScreenScanner
    private let stateBuilder: StateBuilder
    private let keyOutput: any KeyOutput
    private let trigger: any TriggerKeyState
    private let logic: any RuntimeLogic
    private let clock: any RuntimeClock
    private let onSnapshot: @Sendable (RenderSnapshot) -> Void

    private var state: GameState?
    private var className: String?
    private var specName: String?
    private var classId: Int?
    private var specId: Int?
    private var moduleName: String?
    private var scanFailureReason: String?
    private var currentStep = "等待启动"
    private var unitInfo: [String: StateValue] = [:]
    private var target: GameTarget?
    private var enabled = false
    private var clickPending = false
    private var lastRuleSentAt: [String: Duration] = [:]
    private var logicPausedUntil: Duration?
    private var pendingCommands: [Command] = []

    private enum Command: Sendable { case setEnabled(Bool), toggle }

    public init(options: AppOptions, sessionId: UInt64, scanner: any ScreenScanner, stateBuilder: StateBuilder,
                keyOutput: any KeyOutput, trigger: any TriggerKeyState, logic: any RuntimeLogic,
                clock: any RuntimeClock = ContinuousRuntimeClock(), onSnapshot: @escaping @Sendable (RenderSnapshot) -> Void) {
        self.options = options
        self.sessionId = sessionId
        self.scanner = scanner
        self.stateBuilder = stateBuilder
        self.keyOutput = keyOutput
        self.trigger = trigger
        self.logic = logic
        self.clock = clock
        self.onSnapshot = onSnapshot
    }

    public func setEnabled(_ value: Bool) { pendingCommands.append(.setEnabled(value)) }
    public func toggleEnabled() { pendingCommands.append(.toggle) }
    public var isEnabled: Bool { enabled }

    private func applyEnabled(_ value: Bool) {
        enabled = value
        clickPending = false
        if !value {
            lastRuleSentAt.removeAll()
            logicPausedUntil = nil
        }
        currentStep = value ? "手动开启" : "手动关闭"
        publishSnapshot()
    }

    private func drainPendingCommands() {
        let commands = pendingCommands
        pendingCommands.removeAll()
        for command in commands {
            switch command {
            case .setEnabled(let value): applyEnabled(value)
            case .toggle: applyEnabled(!enabled)
            }
        }
    }

    /// 主循环：25ms 轮询触发键；按 logicInterval 执行逻辑；按 renderInterval 发布快照。取消时发布“已停止”。
    public func run() async {
        guard let toggleKey = trigger.resolve(keyName: options.toggleKey) else {
            currentStep = "无法识别触发键: \(options.toggleKey)"
            publishSnapshot()
            return
        }
        var previousPressed = false
        var lastLogicAt: Duration?
        var lastRenderAt: Duration?
        var lastToggleAt: Duration?
        currentStep = "已启动"
        publishSnapshot()

        defer {
            enabled = false
            clickPending = false
            logicPausedUntil = nil
            currentStep = "已停止"
            publishSnapshot()
        }

        while !Task.isCancelled {
            drainPendingCommands()
            let now = clock.now()
            let sample = trigger.read(toggleKey)
            let pressed = sample.isDown
            let rising = ((pressed && !previousPressed) || sample.wasPressed)
                && (lastToggleAt.map { now - $0 >= .milliseconds(120) } ?? true)
            let falling = !pressed && previousPressed

            if rising {
                lastToggleAt = now
                handleRisingEdge()
            }
            if options.mode == .hold {
                enabled = pressed
                if falling {
                    lastRuleSentAt.removeAll()
                    logicPausedUntil = nil
                    currentStep = "按住结束"
                }
            }
            previousPressed = pressed

            if lastLogicAt.map({ now - $0 >= options.logicInterval }) ?? true {
                lastLogicAt = now
                if logicPausedUntil.map({ now >= $0 }) ?? true {
                    await tickLogic(now: now)
                }
            }
            if lastRenderAt.map({ now - $0 >= options.renderInterval }) ?? true {
                lastRenderAt = now
                publishSnapshot()
            }
            do {
                try await clock.sleep(for: .milliseconds(25))
            } catch {
                break
            }
        }
    }

    private func handleRisingEdge() {
        switch options.mode {
        case .click:
            enabled = true
            clickPending = true
            currentStep = "单击触发"
        case .hold:
            enabled = true
            currentStep = "按住触发"
        case .switch:
            enabled.toggle()
            clickPending = false
            if !enabled {
                lastRuleSentAt.removeAll()
                logicPausedUntil = nil
            }
            currentStep = enabled ? "逻辑开启" : "逻辑关闭"
        }
    }

    private func tickLogic(now: Duration) async {
        let scan = await scanner.scan()
        scanFailureReason = scan.failureReason
        target = scan.target

        guard let rowData = scan.rowData else {
            state = nil
            classId = nil
            specId = nil
            className = nil
            specName = nil
            moduleName = nil
            unitInfo = [:]
            if enabled { currentStep = "等待游戏状态" }
            return
        }

        var built = stateBuilder.build(rowData: rowData, barData: scan.barData, healAbsorbData: scan.healAbsorbData)
        classId = built.getInt("职业")
        specId = built.getInt("专精")
        (className, specName) = ClassNames.classAndSpecName(classId: classId, specId: specId)
        if !built.getBool("有效性") {
            state = built
            moduleName = nil
            currentStep = "等待游戏状态"
            unitInfo = [:]
            return
        }

        let evaluation = logic.evaluate(classId: classId, specId: specId, specName: specName, state: &built, runLogic: enabled)
        state = built
        moduleName = evaluation.moduleName

        if !enabled {
            unitInfo = [:]
            return
        }
        guard let decision = evaluation.decision else {
            currentStep = "逻辑未返回决策"
            unitInfo = [:]
            return
        }
        currentStep = decision.step
        unitInfo = decision.unitInfo
        moduleName = decision.moduleName

        if options.mode == .click {
            if clickPending { trySendDecisions(evaluation.decisions, target: scan.target, now: now) }
            enabled = false
            clickPending = false
            return
        }
        trySendDecisions(evaluation.decisions, target: scan.target, now: now)
    }

    private func trySendDecisions(_ decisions: [LogicDecision], target: GameTarget?, now: Duration) {
        for decision in decisions {
            guard let hotkey = decision.hotkey, !hotkey.isBlank else { continue }
            if canSend(decision, now: now) {
                sendAndPauseLogic(decision, hotkey: hotkey, target: target, now: now)
            }
        }
    }

    private func sendAndPauseLogic(_ decision: LogicDecision, hotkey: String, target: GameTarget?, now: Duration) {
        let result = keyOutput.send(hotkey: hotkey, expectedTarget: target)
        if !result.succeeded {
            var info = unitInfo
            info["发送失败"] = .string(result.failureReason ?? "未知原因")
            unitInfo = info
            currentStep = "\(decision.step)（按键发送失败）"
            return
        }
        if decision.delayMs > 0 {
            lastRuleSentAt[rateLimitKey(decision)] = now
        }
        if decision.logicDelayMs > 0 {
            logicPausedUntil = now + .milliseconds(decision.logicDelayMs)
        }
    }

    private func canSend(_ decision: LogicDecision, now: Duration) -> Bool {
        if decision.delayMs <= 0 { return true }
        guard let last = lastRuleSentAt[rateLimitKey(decision)] else { return true }
        return now - last >= .milliseconds(decision.delayMs)
    }

    private func rateLimitKey(_ decision: LogicDecision) -> String {
        decision.rateLimitKey.isNilOrBlank ? (decision.hotkey ?? "") : decision.rateLimitKey!
    }

    private func publishSnapshot() {
        onSnapshot(RenderSnapshot(sessionId: sessionId, enabled: enabled, className: className, specName: specName,
                                  classId: classId, specId: specId, moduleName: moduleName, state: state,
                                  currentStep: currentStep, unitInfo: unitInfo,
                                  dynamicValues: Self.buildDynamicValues(state), scanFailureReason: scanFailureReason, target: target))
    }

    static func buildDynamicValues(_ state: GameState?) -> [DynamicValueSnapshot] {
        guard let state else { return [] }
        var values: [DynamicValueSnapshot] = []
        for (name, slot) in (state.dynamicUnits ?? [:]).sorted(by: { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }) {
            values.append(DynamicValueSnapshot(kind: "单位", name: name, value: formatUnitSlot(state, slot)))
        }
        for (name, value) in (state.dynamicUnitHealth ?? [:]).sorted(by: { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }) {
            values.append(DynamicValueSnapshot(kind: "值名称", name: name, value: value?.displayText ?? "-"))
        }
        for (name, value) in (state.dynamicCounts ?? [:]).sorted(by: { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }) {
            values.append(DynamicValueSnapshot(kind: "数量", name: name, value: String(value)))
        }
        for (name, value) in (state.dynamicValues ?? [:]).sorted(by: { $0.key.caseInsensitiveCompare($1.key) == .orderedAscending }) {
            values.append(DynamicValueSnapshot(kind: "动态值", name: name, value: value?.displayText ?? "-"))
        }
        return values
    }

    static func formatUnitSlot(_ state: GameState, _ slot: String?) -> String {
        guard let slot, !slot.isBlank else { return "-" }
        if let member = state.group[slot], let health = member["生命值"] {
            return "\(slot) (生命值 \(health?.displayText ?? "-"))"
        }
        return slot
    }
}

/// 运行循环使用的时间源：单调时间（自任意起点的时长）+ 可取消的睡眠。测试可注入虚拟时钟。
public protocol RuntimeClock: Sendable {
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

public struct ContinuousRuntimeClock: RuntimeClock {
    private let epoch = ContinuousClock.now
    public init() {}
    public func now() -> Duration { epoch.duration(to: ContinuousClock.now) }
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
