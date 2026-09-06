import Foundation
import Testing
@testable import ShigureCore

@Suite("模块模型、规范化与存储")
struct ModuleTests {
    static let sampleJSON = """
    {
      "Id": "戒律-20260730120000000",
      "Name": "戒律",
      "Author": "模块作者",
      "RecommendedTalent": "推荐天赋代码或说明",
      "Version": "\(AppInfo.version)",
      "UnitMappingVersion": 3,
      "Enabled": true,
      "Match": {
        "ClassId": 5,
        "SpecId": 1,
        "PartyType": "46",
        "HeroTalent": 1
      },
      "Units": [
        {
          "Name": "最低",
          "HealthName": "最低血",
          "Kind": "LowestHealthWithAura",
          "HealthThreshold": 80,
          "Reverse": false,
          "AuraSpellIds": [
            17
          ]
        }
      ],
      "Counts": [
        {
          "Name": "低血人数",
          "Kind": "UnitsBelowHealth",
          "HealthThreshold": 60
        }
      ],
      "ValueAdjustments": [
        {
          "Enabled": true,
          "Condition": "",
          "Field": "阈值",
          "Delta": 0,
          "Formula": "生命值 + 5"
        }
      ],
      "Rules": [
        {
          "Enabled": true,
          "Condition": "生命值 < 50 && spells.17.cooldown == 0",
          "Comment": "",
          "DelayMs": 500,
          "ContinueLogic": true,
          "Unit": 31,
          "Spell": "真言术：盾",
          "MacroCondition": "",
          "Hotkey": "",
          "Step": "自保",
          "SubConditions": [
            "移动"
          ]
        }
      ]
    }
    """

    @Test("解码 → 规范化 → 编码 round-trip 字节一致")
    func roundTrip() throws {
        var module = try ModuleJSON.decode(text: Self.sampleJSON)
        ModuleNormalizer.normalize(&module)
        let encoded = ModuleJSON.encodeText(module)
        #expect(encoded == Self.sampleJSON)
        #expect(module.rules[0].step == "自保", "Hotkey/Step 必须保留")
        #expect(module.rules[0].delayMs == 500)
        #expect(module.units[0].kind == .lowestHealthWithAura)
    }

    @Test("v1 → v3 迁移：31/34 交换、36/37 → 宏条件；Spell 别名迁移；延迟归零")
    func migrations() throws {
        let json = """
        {"Id":"x","Name":"旧","Match":{"PartyType":"团队"},"Rules":[
          {"Unit":31,"Spell":"插入法术","DelayMs":0,"ContinueLogic":false,"SubConditions":["", "  a  "]},
          {"Unit":34,"Spell":"插入物品"},
          {"Unit":36,"Spell":"x"},
          {"Unit":37,"Spell":"y","MacroCondition":"custom"}
        ]}
        """
        var m = try ModuleJSON.decode(text: json)
        ModuleNormalizer.normalize(&m)
        #expect(m.unitMappingVersion == 3)
        #expect(m.match.partyType == "1-40")
        #expect(m.rules[0].unit == 34)
        #expect(m.rules[0].spell == "自动插入法术")
        #expect(m.rules[0].delayMs == nil)
        #expect(m.rules[0].continueLogic == nil)
        #expect(m.rules[0].subConditions == ["a"])
        #expect(m.rules[1].unit == 31)
        #expect(m.rules[1].spell == "自动插入物品")
        #expect(m.rules[2].unit == 0)
        #expect(m.rules[2].macroCondition == "channeling")
        #expect(m.rules[3].unit == 0)
        #expect(m.rules[3].macroCondition == "custom")
        #expect(!m.hasCompatibleVersion)
        // v2 模块不再交换 31/34
        var v2 = try ModuleJSON.decode(text: #"{"Name":"v2","UnitMappingVersion":2,"Rules":[{"Unit":31,"Spell":"s"}]}"#)
        ModuleNormalizer.normalize(&v2)
        #expect(v2.rules[0].unit == 31)
    }

    @Test("PartyType 归一化与匹配")
    func partyType() {
        #expect(ModuleMatch.normalizePartyType("单人") == "0")
        #expect(ModuleMatch.normalizePartyType(" 团队 ") == "1-40")
        #expect(ModuleMatch.normalizePartyType("队伍") == "46")
        #expect(ModuleMatch.normalizePartyType("25") == "1-40")
        #expect(ModuleMatch.normalizePartyType("46") == "46")
        #expect(ModuleMatch.normalizePartyType("40-1") == "1-40")
        #expect(ModuleMatch.normalizePartyType("*") == nil)
        #expect(ModuleMatch.normalizePartyType("any") == nil)
        #expect(ModuleMatch.normalizePartyType("xyz") == "xyz")
        let raid = ModuleMatch(partyType: "1-40")
        #expect(raid.matches(classId: nil, specId: nil, partyType: 20, heroTalent: nil))
        #expect(!raid.matches(classId: nil, specId: nil, partyType: 46, heroTalent: nil))
        #expect(!raid.matches(classId: nil, specId: nil, partyType: nil, heroTalent: nil))
        #expect(ModuleMatch(partyType: "xyz").matches(classId: nil, specId: nil, partyType: 1, heroTalent: nil) == false)
        #expect(ModuleMatch(classId: 5, specId: 1, partyType: "46", heroTalent: 1).specificity == 4)
        #expect(ModuleMatch(partyType: "*").specificity == 0)
    }

    @Test("存储：保存、重名、重命名删除旧文件、选择优先级、文件名清洗")
    func store() throws {
        try Fixtures.withTempDirectory { dir in
            let store = ModuleStore(moduleDirectory: dir.appendingPathComponent("module"))
            var a = ModuleDefinition.createDefault(name: "A/模块:测试  名")
            a.match = ModuleMatch(classId: 5, specId: 1)
            let saved = try store.save(a)
            #expect(saved.fileURL?.lastPathComponent == "A-模块-测试-名.json")
            var b = ModuleDefinition.createDefault(name: "b")
            b.match = ModuleMatch(classId: 5)
            try store.save(b)
            var dup = ModuleDefinition.createDefault(name: "a/模块:测试  名")
            dup.id = "other"
            #expect(throws: ModuleStoreError.self) { try store.save(dup) }

            // 更具体者优先；手选 id 不匹配时回退最佳
            let best = store.findSelectedOrBestMatch(selectedModuleId: nil, classId: 5, specId: 1, partyType: 46, heroTalent: 1)
            #expect(best?.name == "A/模块:测试  名")
            let selected = store.findSelectedOrBestMatch(selectedModuleId: b.id, classId: 5, specId: 1, partyType: 46, heroTalent: 1)
            #expect(selected?.name == "b")
            let fallback = store.findSelectedOrBestMatch(selectedModuleId: b.id, classId: 6, specId: 1, partyType: 0, heroTalent: 1)
            #expect(fallback == nil)

            // 重命名后旧文件删除
            var renamed = saved
            renamed.name = "新名字"
            let saved2 = try store.save(renamed)
            #expect(saved2.fileURL?.lastPathComponent == "新名字.json")
            #expect(!FileManager.default.fileExists(atPath: saved.fileURL!.path))
            #expect(store.getModules().count == 2)

            // 版本过期模块不参与匹配，但显示列表包含
            var old = ModuleDefinition.createDefault(name: "旧")
            old.version = "0.0.1"
            try store.save(old)
            #expect(store.getModules().count == 2)
            #expect(store.getModulesForDisplay().count == 3)
            #expect(store.hasImportIssue(old.id))
            #expect(store.createNextModuleName() == "新模块1")

            try store.delete(saved2)
            store.reload()
            #expect(store.getModulesForDisplay().count == 2)
        }
    }

    @Test("默认模块选择：更具体、更靠后者胜出")
    func defaultModules() {
        let selections = [
            DefaultModuleSelection(classId: 5, moduleId: "m1"),
            DefaultModuleSelection(classId: 5, specId: 1, moduleId: "m2"),
            DefaultModuleSelection(classId: 5, specId: 1, moduleId: "m3"),
            DefaultModuleSelection(classId: 5, specId: 1, partyType: "团队", moduleId: "m4")
        ]
        let matched = selections.enumerated()
            .filter { $0.element.matches(classId: 5, specId: 1, partyType: 46, heroTalent: 1) }
            .sorted { a, b in a.element.specificity != b.element.specificity ? a.element.specificity > b.element.specificity : a.offset > b.offset }
        #expect(matched.first?.element.moduleId == "m3")
    }
}
