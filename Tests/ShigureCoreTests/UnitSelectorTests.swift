import Foundation
import Testing
@testable import ShigureCore

@Suite("动态单位与数量")
struct UnitSelectorTests {
    static func group(_ members: [Int: [String: StateValue?]]) -> GameState {
        var s = GameState()
        var g: [String: [String: StateValue?]] = [:]
        for i in 1...30 {
            g[String(i)] = members[i] ?? ["生命值": .int(0), "职责": .int(0), "驱散": .int(0), "治疗吸收": .int(0), "auras.17.value": .int(0)]
        }
        s.group = g
        return s
    }

    static func member(hp: Int, role: Int = 3, dispel: Int = 0, absorb: Int = 0, aura17: Int = 0) -> [String: StateValue?] {
        ["生命值": .int(hp), "职责": .int(role), "驱散": .int(dispel), "治疗吸收": .int(absorb), "auras.17.value": .int(aura17)]
    }

    @Test("最低生命值：阈值、0/负数、职责 0 跳过、职责缺失不跳过")
    func lowestHealth() {
        var s = Self.group([
            1: Self.member(hp: 30, role: 0),
            2: Self.member(hp: 45),
            3: Self.member(hp: -5),
            4: Self.member(hp: 100)
        ])
        var unit = ModuleUnit()
        unit.name = "u"
        #expect(UnitSelector.resolve(unit, state: s) == "3", "负数血量参与比较")
        unit.healthThreshold = 40
        #expect(UnitSelector.resolve(unit, state: s) == "3")
        s.group["3"] = nil
        unit.healthThreshold = 50
        #expect(UnitSelector.resolve(unit, state: s) == "2", "职责 0 的 1 号被跳过")
        s.group["5"] = ["生命值": .int(10)]
        #expect(UnitSelector.resolve(unit, state: s) == "5", "职责缺失不跳过")
        unit.healthThreshold = 5
        #expect(UnitSelector.resolve(unit, state: s) == nil)
        // 动态阈值优先
        s.dynamicValues = ["阈值": .int(60)]
        unit.healthThresholdField = "阈值"
        #expect(UnitSelector.resolve(unit, state: s) == "5")
        unit.healthThresholdField = "不存在"
        #expect(UnitSelector.resolve(unit, state: s) == nil, "动态阈值不可解析时回退固定值 5")
    }

    @Test("职责筛选与 UnitWithRole 不做 RoleNotZero")
    func roles() {
        var s = Self.group([
            1: Self.member(hp: 50, role: 1),
            2: Self.member(hp: 40, role: 2),
            3: Self.member(hp: 30, role: 0)
        ])
        var unit = ModuleUnit()
        unit.name = "u"
        unit.roleFilter = .exclude
        unit.role = 2
        #expect(UnitSelector.resolve(unit, state: s) == "1")
        unit.roleFilter = .include
        #expect(UnitSelector.resolve(unit, state: s) == "2")
        unit.roleFilter = nil
        unit.kind = .unitWithRole
        unit.role = 0
        #expect(UnitSelector.resolve(unit, state: s) == "3", "UnitWithRole 允许职责 0")
        unit.role = 1
        unit.reverse = true
        s.group["7"] = Self.member(hp: 60, role: 1)
        #expect(UnitSelector.resolve(unit, state: s) == "7")
        unit.reverse = false
        #expect(UnitSelector.resolve(unit, state: s) == "1")
    }

    @Test("光环类：缺光环列 → nil；持续最久/最短；带/不带；层数等于")
    func auras() {
        var s = Self.group([
            1: Self.member(hp: 50, aura17: 5),
            2: Self.member(hp: 40, aura17: 12),
            3: Self.member(hp: 30, aura17: 0)
        ])
        var unit = ModuleUnit()
        unit.name = "u"
        unit.kind = .unitWithAura
        unit.auraSpellIds = [17]
        #expect(UnitSelector.resolve(unit, state: s) == "2")
        unit.kind = .unitWithAuraShortest
        #expect(UnitSelector.resolve(unit, state: s) == "1")
        unit.kind = .lowestHealthWithoutAura
        #expect(UnitSelector.resolve(unit, state: s) == "3")
        unit.kind = .lowestHealthWithAura
        #expect(UnitSelector.resolve(unit, state: s) == "2")
        unit.kind = .lowestHealthWithAuraCount
        unit.auraCount = 5
        #expect(UnitSelector.resolve(unit, state: s) == "1")
        unit.kind = .lowestHealthWithAnyAura
        unit.auraSpellIds = [17, 99]
        #expect(UnitSelector.resolve(unit, state: s) == nil, "任一光环列缺失 → nil")
        unit.auraSpellIds = [99]
        unit.kind = .lowestHealthWithAura
        #expect(UnitSelector.resolve(unit, state: s) == nil)
        for k in s.group.keys { s.group[k]?["auras.17.value"] = nil }
        unit.auraSpellIds = [17]
        #expect(UnitSelector.resolve(unit, state: s) == nil)
    }

    @Test("治疗吸收：选择器要求 >0 且 >阈值，忽略职责筛选；数量统计无 >0")
    func healingAbsorb() {
        let s = Self.group([
            1: Self.member(hp: 50, absorb: 0),
            2: Self.member(hp: 40, role: 1, absorb: 30),
            3: Self.member(hp: 30, absorb: 10)
        ])
        var unit = ModuleUnit()
        unit.name = "u"
        unit.kind = .highestHealingAbsorb
        unit.roleFilter = .exclude
        unit.role = 1
        #expect(UnitSelector.resolve(unit, state: s) == "2", "职责筛选对治疗吸收类无效")
        unit.healthThreshold = 30
        #expect(UnitSelector.resolve(unit, state: s) == nil, "要求严格大于阈值")
        var count = ModuleCountField()
        count.name = "c"
        count.kind = .unitsAboveHealingAbsorb
        count.healthThreshold = -1
        #expect(UnitSelector.resolve(count, state: s) == 3, "阈值 -1 时三名职责非 0 的成员都算；数量无 >0 要求；其余填充成员职责 0 被跳过")
        count.healthThreshold = nil
        #expect(UnitSelector.resolve(count, state: s) == 2)
    }

    @Test("数量：0 < 生命值 < 阈值、光环列缺失 → 0")
    func counts() {
        let s = Self.group([
            1: Self.member(hp: 0),
            2: Self.member(hp: -3),
            3: Self.member(hp: 50, aura17: 1),
            4: Self.member(hp: 70),
            5: Self.member(hp: 99, role: 0)
        ])
        var count = ModuleCountField()
        count.name = "c"
        #expect(UnitSelector.resolve(count, state: s) == 2, "0 与负数不计；职责 0 不计")
        count.healthThreshold = 60
        #expect(UnitSelector.resolve(count, state: s) == 1)
        count.kind = .unitsWithAura
        count.auraSpellId = 17
        #expect(UnitSelector.resolve(count, state: s) == 1)
        count.kind = .unitsWithoutAuraBelowHealth
        count.healthThreshold = 100
        #expect(UnitSelector.resolve(count, state: s) == 1)
        count.auraSpellId = 99
        #expect(UnitSelector.resolve(count, state: s) == 0)
    }

    @Test("驱散类型")
    func dispel() {
        let s = Self.group([2: Self.member(hp: 50, dispel: 3), 4: Self.member(hp: 50, role: 0, dispel: 3)])
        var unit = ModuleUnit()
        unit.name = "u"
        unit.kind = .unitWithDispelType
        unit.dispelType = 3
        #expect(UnitSelector.resolve(unit, state: s) == "2")
        unit.dispelType = 4
        #expect(UnitSelector.resolve(unit, state: s) == nil)
    }

    @Test("摘要文本")
    func summary() {
        var unit = ModuleUnit()
        unit.kind = .lowestHealthWithAura
        unit.auraSpellIds = [17]
        unit.roleFilter = .include
        unit.role = 2
        unit.healthThreshold = 80
        #expect(UnitSummary.describe(unit) { $0 == 17 ? "真言术：盾" : nil } == "职责=2且带[真言术：盾 / 17]且血最低 (<80)")
        unit.kind = .highestHealingAbsorb
        unit.healthThresholdField = "阈值"
        #expect(UnitSummary.describe(unit) == "治疗吸收最高 (>动态:阈值)")
        var count = ModuleCountField()
        count.kind = .unitsWithAuraBelowHealth
        count.auraSpellId = 17
        #expect(UnitSummary.describe(count) == "带[17]且血<100 的人数")
    }
}
