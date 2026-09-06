import Foundation
import Testing
@testable import ShigureCore

@Suite("条件语言")
struct ConditionTests {
    static func state(_ values: [String: StateValue] = [:], spells: [String: StateValue] = [:], auras: [String: StateValue] = [:],
                      group: [String: [String: StateValue?]] = [:]) -> GameState {
        var s = GameState()
        for (k, v) in values { s.setValue(k, v) }
        for (k, v) in spells { s.setSpell(k, v) }
        for (k, v) in auras { s.setAura(k, v) }
        s.group = group
        return s
    }

    static func matched(_ expr: String, _ state: GameState, _ ctx: ConditionEvaluator.Context = .empty) -> Bool? {
        switch ConditionEvaluator.evaluate(expr, state: state, context: ctx) {
        case .matched(let m): return m
        case .error: return nil
        }
    }

    @Test("比较运算符与数值")
    func comparisons() {
        let s = Self.state(["生命值": .int(45), "战斗时间": .int(0), "名字": .string("Abc")])
        #expect(Self.matched("生命值 < 50", s) == true)
        #expect(Self.matched("生命值 <= 45", s) == true)
        #expect(Self.matched("生命值 > 45", s) == false)
        #expect(Self.matched("生命值 >= 46", s) == false)
        #expect(Self.matched("生命值 == 45", s) == true)
        #expect(Self.matched("生命值 != 45", s) == false)
        #expect(Self.matched("战斗时间 > 0", s) == false)
        #expect(Self.matched("名字 == 'abc'", s) == true, "字符串比较大小写不敏感")
        #expect(Self.matched("名字 > 1", s) == false, "非数字关系比较不报错，视为不命中")
        #expect(Self.matched("不存在 < 50", s) == false, "普通缺失字段：nil 不可比较 → 不命中")
        #expect(Self.matched("不存在 == 空", s) == true, "nil == nil 按字符串比较相等")
    }

    @Test("&& 与 || 优先级、空项")
    func precedence() {
        let s = Self.state(["a": .int(1), "b": .int(0), "c": .int(1)])
        #expect(Self.matched("a == 1 && b == 1 || c == 1", s) == true)
        #expect(Self.matched("a == 1 && b == 1", s) == false)
        #expect(Self.matched("a == 0 || b == 0 && c == 0", s) == false)
        #expect(Self.matched("a == 1 && && b == 0", s) == true, "空项为 true")
        #expect(Self.matched("   ", s) == true)
        #expect(Self.matched("", s) == true)
    }

    @Test("裸布尔与取反、字面量转换")
    func booleans() {
        let s = Self.state(["移动": .bool(true), "静止": .bool(false), "零": .int(0), "字符串零": .string("0"), "假串": .string("false")])
        #expect(Self.matched("移动", s) == true)
        #expect(Self.matched("!移动", s) == false)
        #expect(Self.matched("静止", s) == false)
        #expect(Self.matched("!零", s) == true)
        #expect(Self.matched("字符串零", s) == false)
        #expect(Self.matched("假串", s) == false)
        #expect(Self.matched("移动 == true", s) == true)
        #expect(Self.matched("移动 == 是", s) == true)
        #expect(Self.matched("移动 == YES", s) == true)
        #expect(Self.matched("静止 == 否", s) == true)
        #expect(Self.matched("静止 == \"false\"", s) == true, "引号内的 false 是字符串，但按文本比较仍相等")
        #expect(Self.matched("移动 == 1", s) == true, "bool 与数字按数值比较")
    }

    @Test("in / not in")
    func inLists() {
        let s = Self.state(["目标类型": .int(2), "职业": .int(4), "名": .string("x,y")])
        #expect(Self.matched("目标类型 in (1, 2)", s) == true)
        #expect(Self.matched("目标类型 not in (1, 2)", s) == false)
        #expect(Self.matched("职业 not in (4, 9)", s) == false)
        #expect(Self.matched("职业 NOT   IN (1)", s) == true)
        #expect(Self.matched("名 in ('x,y', 'z')", s) == true, "引号保护逗号")
        #expect(Self.matched("目标类型 in ()", s) == false)
        #expect(Self.matched("目标类型 not in ()", s) == true)
        #expect(Self.matched("目标类型 in(1, 2)", s) == true, "in 与括号之间的空白可省略")
        #expect(Self.matched("目标类型in (1, 2)", s) == false, "字段与 in 之间必须有空白，否则退化为裸字段")
    }

    @Test("结构化字段缺失 → 所有运算符 false")
    func structuredMissing() {
        let s = Self.state(spells: ["633.cooldown": .int(0)], auras: ["player.1.value": .int(5)])
        #expect(Self.matched("spells.633.cooldown == 0", s) == true)
        #expect(Self.matched("spell.633.cooldown == 0", s) == true)
        #expect(Self.matched("state.spells.633.cooldown == 0", s) == true)
        #expect(Self.matched("spells.999.cooldown == 0", s) == false)
        #expect(Self.matched("spells.999.cooldown != 0", s) == false)
        #expect(Self.matched("spells.999.cooldown not in (1)", s) == false)
        #expect(Self.matched("!spells.999.cooldown", s) == false)
        #expect(Self.matched("auras.player.1.value > 0", s) == true)
        #expect(Self.matched("auras.target.harmful.2.value > 0", s) == false)
        #expect(Self.matched("auras.target.harmful.2.value == 空", s) == false)
    }

    @Test("group、动态单位、数量、动态值解析优先级")
    func dynamicFields() {
        var s = Self.state(group: [
            "1": ["生命值": .int(40), "职责": .int(2), "auras.17.value": .int(3)],
            "2": ["生命值": .int(90), "职责": .int(1)]
        ])
        s.dynamicUnits = ["最低": "1", "无": nil]
        s.dynamicUnitHealth = ["最低血": .int(40)]
        s.dynamicCounts = ["低血人数": 3]
        s.dynamicValues = ["动态": .int(7), "最低血": .int(999)]
        #expect(Self.matched("group.1.生命值 < 50", s) == true)
        #expect(Self.matched("group.1.auras.17.value > 0", s) == true)
        #expect(Self.matched("group.3.生命值 < 50", s) == false)
        #expect(Self.matched("最低.生命值 < 50", s) == true)
        #expect(Self.matched("最低", s) == true)
        #expect(Self.matched("无", s) == false)
        #expect(Self.matched("无.生命值 < 50", s) == false)
        #expect(Self.matched("低血人数 >= 3", s) == true)
        #expect(Self.matched("最低血 < 50", s) == true, "$unithealth 优先于 $dynamicvalues")
        #expect(Self.matched("动态 == 7", s) == true)
    }

    @Test("spellId 字段转本地索引")
    func spellIdFields() {
        let s = Self.state(["一键辅助": .int(12), "插入物品": .int(3)])
        let ctx = ConditionEvaluator.Context(spellIndices: [8122: 12], itemIndices: [241288: 3])
        #expect(Self.matched("一键辅助 == 8122", s, ctx) == true)
        #expect(Self.matched("一键辅助 != 8122", s, ctx) == false)
        #expect(Self.matched("一键辅助 == 999", s, ctx) == false, "找不到 spellId → 不命中")
        #expect(Self.matched("state.一键辅助 == 8122", s, ctx) == true)
        #expect(Self.matched("插入物品 == 241288", s, ctx) == true)
        #expect(Self.matched("一键辅助 > 1", s, ctx) == nil, "只允许 == / != → 错误")
        #expect(Self.matched("一键辅助 in (8122)", s, ctx) == nil)
    }

    @Test("自动插入法术 / 自动插入物品 作为条件字段")
    func failedSpellFields() {
        let s = Self.state(["插入法术": .int(2), "插入物品": .int(1), "治疗石": .int(0)], spells: ["47540.cooldown": .int(0)])
        var st = s
        st.itemIds = ["治疗石": 5512]
        let ctx = ConditionEvaluator.Context(failedSpells: [2: 47540], insertItems: [1: 5512])
        #expect(Self.matched("自动插入法术", st, ctx) == true)
        #expect(Self.matched("自动插入法术 == 47540", st, ctx) == true)
        #expect(Self.matched("自动插入物品 == 5512", st, ctx) == true)
        var busy = st
        busy.setValue("治疗石", .int(30))
        #expect(Self.matched("自动插入物品", busy, ctx) == false)
    }

    @Test("规则：主条件 && (子条件 || ...)")
    func rules() {
        let s = Self.state(["a": .int(1), "b": .int(0), "c": .int(1)])
        var rule = ModuleRule()
        rule.condition = "a == 1"
        rule.subConditions = ["b == 1", "c == 1"]
        #expect(ConditionEvaluator.evaluateRule(rule, state: s) == .matched(true))
        rule.subConditions = ["b == 1"]
        #expect(ConditionEvaluator.evaluateRule(rule, state: s) == .matched(false))
        rule.subConditions = ["  "]
        #expect(ConditionEvaluator.evaluateRule(rule, state: s) == .matched(false), "只有空白子条件 → 无子条件命中")
        rule.condition = "a == 0"
        rule.subConditions = ["c == 1"]
        #expect(ConditionEvaluator.evaluateRule(rule, state: s) == .matched(false))
        rule.condition = "一键辅助 > 1"
        #expect({ if case .error = ConditionEvaluator.evaluateRule(rule, state: s) { return true }; return false }())
    }

    @Test("文本 ⇄ 可视化 round-trip")
    func roundTrip() {
        let text = "生命值 < 50 && spells.633.cooldown == 0 || 目标类型 in (1, 2) && !移动"
        let terms = ConditionExpression.parse(text)
        #expect(terms.count == 4)
        #expect(terms[0] == ConditionTerm(field: "生命值", op: "<", value: "50"))
        #expect(terms[1] == ConditionTerm(field: "spells.633.cooldown", op: "==", value: "0"))
        #expect(terms[2] == ConditionTerm(field: "目标类型", op: "in", value: "1, 2", orWithPrevious: true))
        #expect(terms[3] == ConditionTerm(field: "移动", op: "==", value: "false"))
        #expect(ConditionExpression.build(terms) == "生命值 < 50 && spells.633.cooldown == 0 || 目标类型 in (1, 2) && 移动 == false")
        #expect(ConditionExpression.build([ConditionTerm(field: "", op: "==", value: "1"), ConditionTerm(field: "x", op: ">", value: "")]) == "")
    }
}

@Suite("公式")
struct FormulaTests {
    static let state: GameState = {
        var s = GameState()
        s.setValue("生命值", .int(45))
        s.setValue("法力值", .int(80))
        s.setSpell("633.cooldown", .int(3))
        s.dynamicCounts = ["人数": 4]
        return s
    }()

    static func eval(_ expr: String) -> Int? {
        if case .success(let v) = FormulaEvaluator.evaluateInt(expr, state: state) { return v }
        return nil
    }

    static func error(_ expr: String) -> String? {
        if case .failure(let e) = FormulaEvaluator.evaluateInt(expr, state: state) { return e.message }
        return nil
    }

    @Test("算术、优先级、括号、一元")
    func arithmetic() {
        #expect(Self.eval("1 + 2 * 3") == 7)
        #expect(Self.eval("(1 + 2) * 3") == 9)
        #expect(Self.eval("-生命值 + 100") == 55)
        #expect(Self.eval("+法力值 / 2") == 40)
        #expect(Self.eval("7 / 2") == 3, "结果向零截断")
        #expect(Self.eval("-7 / 2") == -3)
        #expect(Self.eval("spells.633.cooldown * 人数") == 12)
    }

    @Test("函数：银行家舍入、截断、floor/ceil/min/max")
    func functions() {
        #expect(Self.eval("round(2.5)") == 2)
        #expect(Self.eval("round(3.5)") == 4)
        #expect(Self.eval("round(-2.5)") == -2)
        #expect(Self.eval("int(2.9)") == 2)
        #expect(Self.eval("int(-2.9)") == -2)
        #expect(Self.eval("floor(-2.1)") == -3)
        #expect(Self.eval("ceil(2.1)") == 3)
        #expect(Self.eval("min(3, 1, 2)") == 1)
        #expect(Self.eval("MAX(生命值, 法力值)") == 80)
    }

    @Test("注释、赋值拆分、错误")
    func misc() {
        #expect(Self.eval("生命值 + 1 # 注释") == 46)
        #expect(Self.eval("阈值 = 生命值 + 5") == 50)
        let split = FormulaEvaluator.splitAssignment("阈值 = 生命值 + 5")
        #expect(split?.field == "阈值" && split?.formula == "生命值 + 5")
        #expect(FormulaEvaluator.splitAssignment("生命值 + 5") == nil)
        #expect(Self.error("") == "公式为空。")
        #expect(Self.error("1 / 0")?.hasPrefix("公式中出现除以 0。") == true)
        #expect(Self.error("不存在 + 1")?.hasPrefix("无法读取数值“不存在”。") == true)
        #expect(Self.error("abs(1)")?.hasPrefix("不支持函数“abs”。") == true)
        #expect(Self.error("1 +")?.hasPrefix("公式不完整。") == true)
        #expect(Self.error("(1")?.hasPrefix("缺少“)”。") == true)
    }
}
