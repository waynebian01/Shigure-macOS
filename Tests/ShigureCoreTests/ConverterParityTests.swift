import Foundation
import Testing
@testable import ShigureCore

@Suite("Fuyutsui → config/keymap 转换对齐")
struct ConverterParityTests {
    /// 仓库内 config/*.json 生成于 2026-09-01。之后 class/*.lua 于 09-02 新增「特殊」分类（符文/酒池/图腾等从「状态」迁出，
    /// 影响 战士/圣骑士/牧师/死亡骑士/萨满/武僧/德鲁伊/恶魔猎手），09-05 修正了牧师 spellsList 索引。
    /// 只有 猎人/潜行者/法师/术士/唤魔师 的 Lua 未再变动，可做逐字节对照。
    static let configFixtureCurrentClassIds = [3, 4, 8, 9, 13]

    @Test("config JSON 与仓库生成文件逐字节一致", arguments: configFixtureCurrentClassIds)
    func configBytesMatch(classId: Int) throws {
        let fileName = ClassNames.configFileName(classId)
        let lua = try Fixtures.text("Fuyutsui/class/\(fileName).lua")
        let expectedData = try Fixtures.data("config/\(fileName).json")
        // 转换器保留现有文件中的 keymap/一键法术/一键物品；与 C# 相同，先读旧文件再覆盖。
        var existing = try JSONParser.parseObject(TextFile.decode(expectedData))
        // 仓库内 config/*.json 生成于转换器加入 `一键物品` 输出之前（2026-09-01），该键在旧文件中缺失或为空。
        // 这里把它从两侧剔除做字节比对，并单独校验 `一键物品` 的内容来自 Lua itemsList。
        let expectedHadItemMap = existing.contains("一键物品")
        existing.remove("一键物品")
        var (root, warnings) = try FuyutsuiConfigConverter.compileClass(lua: lua, fileName: fileName, existing: existing)
        let itemMap = try #require(root.object("一键物品"), "转换器应始终输出 一键物品")
        let itemsList = try #require(LuaLiteParser.extractAssignedTable(lua, "Fuyutsui.itemsList"))
        let luaItemIds = Set(itemsList.entries.compactMap { $0.key?.intValue })
        #expect(Set(itemMap.entries.compactMap { JSONHelpers.getLong($0.value) }) == luaItemIds, "\(fileName) 一键物品 应覆盖 itemsList 全部 itemId")
        root.remove("一键物品")
        let produced = "\u{FEFF}" + JSONWriter.indented(.object(root)) + "\n"
        var expected = String(decoding: expectedData, as: UTF8.self)
        if expectedHadItemMap {
            expected = expected.replacingOccurrences(of: "  \"一键物品\": {},\n", with: "")
        }
        if produced != expected {
            let p = produced.split(separator: "\n", omittingEmptySubsequences: false)
            let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
            var firstDiff = "(无差异行，长度不同: \(p.count) vs \(e.count))"
            for i in 0..<min(p.count, e.count) where p[i] != e[i] {
                firstDiff = "第 \(i + 1) 行\n生成: \(p[i])\n期望: \(e[i])"
                break
            }
            Issue.record("\(fileName).json 不一致：\(firstDiff)\n警告: \(warnings)")
        }
    }

    @Test("common.json 生成格式一致")
    func commonConfig() throws {
        try Fixtures.withTempDirectory { dir in
            try FuyutsuiConfigConverter.ensureCommonConfig(dir)
            let produced = try Data(contentsOf: dir.appendingPathComponent("common.json"))
            let expected = try Fixtures.data("config/common.json")
            #expect(produced == expected)
        }
    }

    /// 仓库内 keymap/*.json 生成于 2026-08-28；之后 classmacros.lua 修改了圣骑士动态宏、德鲁伊与恶魔猎手静态/特殊宏，
    /// 这三个职业的旧文件无法作为对照。其余 10 个职业的槽位语义必须一致。
    static let keymapFixtureCurrentClassIds = ClassNames.allClasses.map(\.id).filter { ![2, 11, 12].contains($0) }

    @Test("keymap 转换与仓库文件在共有槽位上一致", arguments: keymapFixtureCurrentClassIds)
    func keymapSlotsMatch(classId: Int) throws {
        let lua = try Fixtures.text("Fuyutsui/core/classmacros.lua")
        let classMacros = try #require(LuaLiteParser.extractAssignedTable(lua, "Fuyutsui.ClassMacros"))
        let classFile = ClassMacrosStore.classFileKey(classId: classId)
        let classTable = try #require(classMacros.table(classFile))
        let fileName = ClassNames.configFileName(classId).lowercased() + ".json"
        let expectedURL = Fixtures.url("keymap/\(fileName)")
        let existing = FuyutsuiKeymapConverter.loadExistingSpellNames(expectedURL)
        let (root, _) = FuyutsuiKeymapConverter.compileClassKeymap(classTable, existing: existing, classFile: classFile, classId: classId)
        let expectedRoot = try JSONParser.parseObject(TextFile.read(expectedURL))

        // 仓库文件基于旧的 39 键池（273 槽）；热键字符串不可比，只比较槽位语义（unit/技能/宏条件）。
        func compare(_ produced: JSONObject, _ expected: JSONObject, context: String) {
            var mismatches: [String] = []
            for (slot, node) in expected.entries {
                guard Int(slot) != nil, case .object(let exp) = node else { continue }
                guard case .object(let got)? = produced[slot] else {
                    mismatches.append("\(context)[\(slot)] 缺失")
                    continue
                }
                for key in ["unit", "技能", "宏条件"] where got[key] != exp[key] {
                    mismatches.append("\(context)[\(slot)].\(key): 生成 \(got[key].map(JSONWriter.compact) ?? "nil") 期望 \(exp[key].map(JSONWriter.compact) ?? "nil")")
                }
            }
            if !mismatches.isEmpty {
                Issue.record("\(fileName) \(mismatches.count) 处不一致，首个: \(mismatches[0])")
            }
        }
        compare(root, expectedRoot, context: "root")
        if let expectedSpecs = expectedRoot.object("专精") {
            let producedSpecs = try #require(root.object("专精"))
            for (specId, node) in expectedSpecs.entries {
                guard case .object(let exp) = node, case .object(let got)? = producedSpecs[specId] else {
                    Issue.record("\(fileName) 缺少专精 \(specId)")
                    continue
                }
                compare(got, exp, context: "专精[\(specId)]")
            }
        }
    }

    @Test("热键池 350 槽且顺序为修饰符外层")
    func macroKind() {
        #expect(KeymapCatalog.macroSlotCapacity == 350)
        #expect(KeymapCatalog.macroKind.count == 350)
        #expect(KeymapCatalog.macroKind[0] == "CTRL-NUMPAD1")
        #expect(KeymapCatalog.macroKind[49] == "CTRL-RIGHT")
        #expect(KeymapCatalog.macroKind[50] == "ALT-NUMPAD1")
        #expect(KeymapCatalog.macroKind[349] == "ALT-CTRL-SHIFT-RIGHT")
    }

    @Test("DeriveSpellName 各分支")
    func deriveSpellName() {
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/stopcasting") == "停止施法")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/castsequence reset=combat x, 圣光术, 圣光闪现") == "圣光术")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/castsequence [@player] 真言术：盾, 苦修") == "真言术：盾")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("item:241300\n/cast item:241301") == "item:241300")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/cancelaura 冰箱\n/cast 寒冰屏障") == "寒冰屏障")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/cast [@focus,harm] 拳击; [@target] 拳击") == "拳击")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("/cast [@cursor]勇士之矛") == "勇士之矛")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("英勇投掷") == "英勇投掷")
        #expect(FuyutsuiKeymapConverter.deriveSpellName("   ") == "")
    }

    @Test("ParseStaticMacro 目标与条件")
    func parseStaticMacro() {
        let p1 = FuyutsuiKeymapConverter.parseStaticMacro("/cast [@player]荣耀圣令")
        #expect(p1 == .init(unit: 31, spell: "荣耀圣令", condition: ""))
        let p2 = FuyutsuiKeymapConverter.parseStaticMacro("/cast [@party2,nochanneling] 清毒术")
        #expect(p2.unit == 3)
        #expect(p2.condition == "nochanneling")
        let p3 = FuyutsuiKeymapConverter.parseStaticMacro("/cast [channeling] 停止", comment: "手填名")
        #expect(p3.spell == "手填名")
        #expect(p3.unit == 0)
        let p4 = FuyutsuiKeymapConverter.parseStaticMacro("/cast [@raid30] 救赎")
        #expect(p4.unit == 30)
        let special = FuyutsuiKeymapConverter.parseSpecialMacro("/cast [@target] 任意", comment: " 特殊名 ")
        #expect(special == .init(unit: 0, spell: "特殊名", condition: ""))
    }
}
