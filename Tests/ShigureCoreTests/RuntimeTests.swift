import Foundation
import Testing
@testable import ShigureCore

@Suite("状态构建与像素解码")
struct StateAndPixelTests {
    @Test("StateBuilder：字段、bar、光环别名、队伍偏移与治疗吸收扣减")
    func stateBuilder() throws {
        try Fixtures.withTempDirectory { dir in
            let paths = try Fixtures.makePaths(dir)
            let config = try ConfigService.load(configDirectory: paths.configDirectory)
            let builder = StateBuilder(config: config)
            // 牧师戒律：职业 5 专精 1；group.start=78 num=5；玩家光环 450193 在 step 41；47540.count 为 bar 1
            var row: [Int: Int] = [1: 1, 2: 5, 3: 1, 4: 46, 6: 1, 41: 9]
            let memberBase = 78
            row[memberBase + 1] = 60      // 成员 1 生命值
            row[memberBase + 2] = 2       // 职责
            row[memberBase + 5 + 1] = 90  // 成员 2 生命值
            let state = builder.build(rowData: row, barData: [1: 2], healAbsorbData: [1: 15])
            #expect(state.getInt("职业") == 5)
            #expect(state.getInt("专精") == 1)
            #expect(state.getBool("锚点") == true)
            #expect(state.getBool("有效性") == true)
            #expect(state.getInt("队伍类型") == 46)
            #expect(state.auras["player.450193.value"] == .int(9))
            #expect(state.spells["47540.count"] == .int(2))
            #expect(state.spells["8122.cooldown"] == .int(0), "缺失像素等于 0")
            #expect(state.spellDisplayTypes["47540.count"] == "充能层数")
            #expect(state.group["1"]?["生命值"] == .int(45), "生命值 60 - 治疗吸收 15")
            #expect(state.group["1"]?["治疗吸收"] == .int(15))
            #expect(state.group["1"]?["职责"] == .int(2))
            #expect(state.group["2"]?["生命值"] == .int(90))
            #expect(state.group.count == 30)
            #expect(state.group["1"]?.keys.contains("auras.17.value") == true, "多 ID 光环别名 17/1253593 都可查")
            #expect(state.group["1"]?.keys.contains("auras.1253593.value") == true)
            #expect(!state.itemIds.isEmpty)
        }
    }

    static func topRowPixel(step: Int, value: UInt8) -> (UInt8, UInt8, UInt8) {
        step <= 255 ? (0, UInt8(step), value) : (1, UInt8(step - 255), value)
    }

    @Test("像素解码：顶行、CountBars、治疗吸收，1x 与 2x")
    func pixelDecoder() {
        for scale in [1, 2] {
            let width = 60 * scale
            func rep(_ px: (UInt8, UInt8, UInt8), _ n: Int = 1) -> [(UInt8, UInt8, UInt8)] { Array(repeating: px, count: n * scale) }
            var top: [(UInt8, UInt8, UInt8)] = []
            top += rep((0, 0, 0), 2)  // 左侧偏移，锚点不在 x=0
            top += rep(Self.topRowPixel(step: 1, value: 1))
            top += rep(Self.topRowPixel(step: 2, value: 5))
            top += rep(Self.topRowPixel(step: 3, value: 1))
            top += rep(Self.topRowPixel(step: 300, value: 77))
            top += rep(Self.topRowPixel(step: 510, value: 9))
            top += rep(Self.topRowPixel(step: 4, value: 99)) // 510 之后不再读取
            top += rep((0, 0, 0), max(0, 60 - 8))
            // CountBars 行：段 1 值 3（红→(1,1,0)→白×3→背景 G=4），段 2 值 0（白后直接非白 G=1），灰终止
            var bars: [(UInt8, UInt8, UInt8)] = []
            bars += rep((1, 0, 0)) + rep((1, 1, 0)) + rep((255, 255, 255), 3) + rep((1, 4, 0)) + rep((1, 5, 0))
            bars += rep((1, 0, 0)) + rep((255, 255, 255), 1) + rep((1, 1, 0))
            bars += rep((200, 200, 200))
            bars += rep((0, 0, 0), max(0, 60 - 10))
            // 治疗吸收：逻辑行 0 单位 2 值 25（G=26）；逻辑行 1 单位 7 值 0
            var absorb0: [(UInt8, UInt8, UInt8)] = rep((0, 2, 0)) + rep((255, 255, 255), 2) + rep((0, 26, 2)) + rep((200, 200, 200))
            absorb0 += rep((0, 0, 0), 60 - 5)
            var absorb1: [(UInt8, UInt8, UInt8)] = rep((1, 7, 0)) + rep((255, 255, 255), 1) + rep((1, 1, 7)) + rep((200, 200, 200))
            absorb1 += rep((0, 0, 0), 60 - 4)
            var rows: [[(UInt8, UInt8, UInt8)]] = []
            if scale == 2 { rows.append(Array(repeating: (0, 0, 0), count: width)) } // Retina 下顶部可能有一行非锚点
            for _ in 0..<scale { rows.append(Array(top.prefix(width))) }
            for _ in 0..<(2 * scale) { rows.append(Array(bars.prefix(width))) }
            for _ in 0..<(2 * scale) { rows.append(Array(absorb0.prefix(width))) }
            for _ in 0..<(2 * scale) { rows.append(Array(absorb1.prefix(width))) }
            rows.append(Array(repeating: (0, 0, 0), count: width))
            let buffer = PixelBuffer.make(rows: rows)
            let decoded = PixelDecoder.decode(buffer)
            #expect(decoded.failureReason == nil, "scale \(scale): \(decoded.failureReason ?? "")")
            #expect(decoded.rowData[1] == 1)
            #expect(decoded.rowData[2] == 5)
            #expect(decoded.rowData[300] == 77)
            #expect(decoded.rowData[510] == 9)
            #expect(decoded.rowData[4] == nil, "step 510 之后停止")
            #expect(decoded.barData == [1: 3, 2: 0], "scale \(scale)")
            #expect(decoded.healAbsorbData == [2: 25, 7: 0], "scale \(scale)")
        }
    }

    @Test("像素解码失败路径")
    func pixelFailures() {
        let empty = PixelBuffer.make(rows: [Array(repeating: (0, 0, 0), count: 10), Array(repeating: (0, 0, 0), count: 10)])
        #expect(PixelDecoder.decode(empty).failureReason == "未找到有效的状态像素起始标记")
        let noMarker = PixelBuffer.make(rows: [[Self.topRowPixel(step: 1, value: 1), Self.topRowPixel(step: 2, value: 5)], [(0, 0, 0), (0, 0, 0)]])
        let d = PixelDecoder.decode(noMarker)
        #expect(d.rowData[2] == 5)
        #expect(d.failureReason == "未找到 CountBars 标记, 层数条和治疗吸收数据未采集")
    }
}

// MARK: - 运行时循环（虚拟时钟）

final class ManualClock: RuntimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    /// 每次 sleep 推进虚拟时间；到达 stopAfter 后取消任务。
    var stopAfter: Duration = .seconds(10)
    var onTick: (@Sendable (Duration) -> Void)?

    func now() -> Duration { lock.withLock { current } }

    func sleep(for duration: Duration) async throws {
        let next: Duration = lock.withLock {
            current += duration
            return current
        }
        onTick?(next)
        if next >= stopAfter { throw CancellationError() }
        await Task.yield()
    }
}

final class FakeTrigger: TriggerKeyState, @unchecked Sendable {
    private let lock = NSLock()
    private var down = false
    private var pressedLatch = false
    func resolve(keyName: String) -> TriggerKeyCode? {
        keyName == "BAD" ? nil : TriggerKeyCode(kind: .mouseButton(4), name: keyName)
    }
    func read(_ key: TriggerKeyCode) -> TriggerKeySample {
        lock.withLock {
            let sample = TriggerKeySample(isDown: down, wasPressed: pressedLatch)
            pressedLatch = false
            return sample
        }
    }
    func set(down value: Bool) { lock.withLock { down = value } }
    func click() { lock.withLock { pressedLatch = true } }
}

final class FakeScanner: ScreenScanner, @unchecked Sendable {
    var rowData: [Int: Int]? = [1: 1, 2: 5, 3: 1, 6: 1]
    func scan() async -> ScreenScanResult {
        ScreenScanResult(rowData: rowData, target: GameTarget(pid: 1, windowID: 1, bounds: .zero, bundleURL: nil))
    }
}

final class FakeKeyOutput: KeyOutput, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sent: [String] = []
    var failNext = false
    func send(hotkey: String, expectedTarget: GameTarget?) -> KeySendResult {
        lock.withLock {
            if failNext { failNext = false; return .failure("模拟失败") }
            sent.append(hotkey)
            return .success
        }
    }
    var count: Int { lock.withLock { sent.count } }
}

struct FakeLogic: RuntimeLogic {
    var decisions: [LogicDecision]
    func evaluate(classId: Int?, specId: Int?, specName: String?, state: inout GameState, runLogic: Bool) -> LogicEvaluation {
        LogicEvaluation(moduleName: "测试模块", decisions: runLogic ? decisions : [])
    }
}

@Suite("运行时循环")
struct RuntimeLoopTests {
    static func makeConfig() throws -> ConfigService {
        var root = JSONObject()
        root["锚点"] = .object(JSONObject([("step", .int(1)), ("type", .string("bool"))]))
        root["职业"] = .object(JSONObject([("step", .int(2)), ("type", .string("int"))]))
        root["专精"] = .object(JSONObject([("step", .int(3)), ("type", .string("int"))]))
        var spec = JSONObject()
        spec["有效性"] = .object(JSONObject([("step", .int(6)), ("type", .string("bool"))]))
        var cls = JSONObject()
        cls["1"] = .object(spec)
        root["5"] = .object(cls)
        return ConfigService(root: root)
    }

    struct Harness {
        let clock = ManualClock()
        let trigger = FakeTrigger()
        let scanner = FakeScanner()
        let keys = FakeKeyOutput()
        let snapshots = SnapshotSink()

        func runtime(mode: SendMode, decisions: [LogicDecision], toggleKey: String = "XBUTTON2") throws -> ShigureRuntime {
            let sink = snapshots
            return ShigureRuntime(options: AppOptions(toggleKey: toggleKey, mode: mode), sessionId: 7, scanner: scanner,
                                  stateBuilder: StateBuilder(config: try Self.config()), keyOutput: keys, trigger: trigger,
                                  logic: FakeLogic(decisions: decisions), clock: clock) { sink.append($0) }
        }
        static func config() throws -> ConfigService { try RuntimeLoopTests.makeConfig() }
    }

    final class SnapshotSink: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [RenderSnapshot] = []
        func append(_ s: RenderSnapshot) { lock.withLock { items.append(s) } }
        var all: [RenderSnapshot] { lock.withLock { items } }
    }

    static let cast = LogicDecision(hotkey: "CTRL-F1", step: "测试模块: 施放 X", unitInfo: [:], moduleName: "测试模块")

    @Test("switch 模式：上升沿切换，禁用时不发送；触发键去抖 120ms")
    func switchMode() async throws {
        let h = Harness()
        let runtime = try h.runtime(mode: .switch, decisions: [Self.cast])
        h.clock.stopAfter = .milliseconds(1000)
        h.clock.onTick = { now in
            h.trigger.set(down: now >= .milliseconds(200) && now < .milliseconds(250))
        }
        await runtime.run()
        let snaps = h.snapshots.all
        #expect(snaps.first?.currentStep == "已启动")
        #expect(snaps.last?.currentStep == "已停止")
        #expect(snaps.contains { $0.enabled }, "上升沿后启用")
        #expect(snaps.contains { !$0.enabled && $0.currentStep == "已启动" })
        #expect(h.keys.count > 0, "启用后按 100ms 逻辑间隔发送")
        #expect(snaps.allSatisfy { $0.sessionId == 7 })
        // 750ms 内以 100ms 间隔最多 8 次
        #expect(h.keys.count <= 9)
    }

    @Test("click 模式：每次点击只发送一轮；wasPressed 捕获短促点击")
    func clickMode() async throws {
        let h = Harness()
        let runtime = try h.runtime(mode: .click, decisions: [Self.cast])
        h.clock.stopAfter = .milliseconds(1000)
        h.clock.onTick = { now in
            if now == .milliseconds(200) || now == .milliseconds(600) { h.trigger.click() }
        }
        await runtime.run()
        #expect(h.keys.count == 2)
        #expect(h.snapshots.all.allSatisfy { !$0.enabled }, "单击发送后立即禁用，快照不会看到启用态")
    }

    @Test("hold 模式：按住期间启用，松开停止")
    func holdMode() async throws {
        let h = Harness()
        let runtime = try h.runtime(mode: .hold, decisions: [Self.cast])
        h.clock.stopAfter = .milliseconds(1000)
        h.clock.onTick = { now in
            if now >= .milliseconds(200) && now < .milliseconds(500) { h.trigger.set(down: true) } else { h.trigger.set(down: false) }
        }
        await runtime.run()
        #expect(h.keys.count >= 2 && h.keys.count <= 4)
        #expect(h.snapshots.all.contains { $0.currentStep == "按住结束" })
    }

    @Test("DelayMs 限流与 LogicDelayMs 暂停")
    func delays() async throws {
        let h = Harness()
        let limited = LogicDecision(hotkey: "A", step: "s", unitInfo: [:], moduleName: "m", delayMs: 300, rateLimitKey: "m:0")
        let pausing = LogicDecision(hotkey: "B", step: "s", unitInfo: [:], moduleName: "m", logicDelayMs: 400)
        let runtime = try h.runtime(mode: .switch, decisions: [limited, pausing])
        h.clock.stopAfter = .milliseconds(1100)
        h.clock.onTick = { now in h.trigger.set(down: now >= .milliseconds(50) && now < .milliseconds(100)) }
        await runtime.run()
        let sent = h.keys.sent
        // 每次逻辑 tick 发 A（受 300ms 限流）与 B（发送后暂停 400ms）；总时长 1s → 约 2 轮
        #expect(sent.filter { $0 == "B" }.count >= 2 && sent.filter { $0 == "B" }.count <= 3)
        #expect(sent.filter { $0 == "A" }.count <= sent.filter { $0 == "B" }.count)
    }

    @Test("发送失败写入 发送失败 并标记步骤")
    func sendFailure() async throws {
        let h = Harness()
        let runtime = try h.runtime(mode: .switch, decisions: [Self.cast])
        h.keys.failNext = true
        h.clock.stopAfter = .milliseconds(400)
        h.clock.onTick = { now in h.trigger.set(down: now >= .milliseconds(50) && now < .milliseconds(100)) }
        await runtime.run()
        #expect(h.snapshots.all.contains { $0.unitInfo["发送失败"] == .string("模拟失败") && $0.currentStep.hasSuffix("（按键发送失败）") })
    }

    @Test("无法识别触发键；扫描失败时等待游戏状态；有效性为假不评估")
    func edgeCases() async throws {
        let h = Harness()
        let bad = try h.runtime(mode: .switch, decisions: [], toggleKey: "BAD")
        await bad.run()
        #expect(h.snapshots.all.last?.currentStep == "无法识别触发键: BAD")

        let h2 = Harness()
        h2.scanner.rowData = nil
        let rt = try h2.runtime(mode: .switch, decisions: [Self.cast])
        h2.clock.stopAfter = .milliseconds(400)
        h2.clock.onTick = { now in h2.trigger.set(down: now >= .milliseconds(50) && now < .milliseconds(100)) }
        await rt.run()
        #expect(h2.snapshots.all.contains { $0.currentStep == "等待游戏状态" })
        #expect(h2.keys.count == 0)

        let h3 = Harness()
        h3.scanner.rowData = [1: 1, 2: 5, 3: 1, 6: 0]
        let rt3 = try h3.runtime(mode: .switch, decisions: [Self.cast])
        h3.clock.stopAfter = .milliseconds(400)
        h3.clock.onTick = { now in h3.trigger.set(down: now >= .milliseconds(50) && now < .milliseconds(100)) }
        await rt3.run()
        #expect(h3.keys.count == 0)
        #expect(h3.snapshots.all.contains { $0.className == "牧师" && $0.specName == "戒律" })
    }

    @Test("协调器：重启 latest-wins，快照带会话 id，停止后发出 stopped")
    func coordinator() async throws {
        let sink = SnapshotSink()
        let clock = ManualClock()
        clock.stopAfter = .seconds(3600)
        let coordinator = RuntimeCoordinator { options, id, publish in
            ShigureRuntime(options: options, sessionId: id, scanner: FakeScanner(), stateBuilder: StateBuilder(config: try! RuntimeLoopTests.makeConfig()),
                           keyOutput: FakeKeyOutput(), trigger: FakeTrigger(), logic: FakeLogic(decisions: []), clock: clock, onSnapshot: publish)
        }
        let events = await coordinator.events()
        let collector = Task<[UInt64], Never> {
            var stopped: [UInt64] = []
            for await event in events {
                switch event {
                case .snapshot(let s): sink.append(s)
                case .stopped(let id): stopped.append(id); if stopped.count == 2 { return stopped }
                case .failed: break
                }
            }
            return stopped
        }
        await coordinator.start(AppOptions())
        #expect(await coordinator.isRunning)
        #expect(await coordinator.currentSessionId == 1)
        await coordinator.restart(AppOptions(mode: .click))
        #expect(await coordinator.currentSessionId == 2)
        #expect(await coordinator.currentOptions?.mode == .click)
        await coordinator.stop()
        #expect(await !coordinator.isRunning)
        let stopped = await collector.value
        #expect(stopped == [1, 2])
        #expect(sink.all.contains { $0.sessionId == 1 } && sink.all.contains { $0.sessionId == 2 })
    }
}
