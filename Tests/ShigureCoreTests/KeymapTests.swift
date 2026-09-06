import Foundation
import Testing
@testable import ShigureCore

@Suite("Keymap 解析与热键")
struct KeymapTests {
    @Test("热键字符串解析：前缀消费")
    func parseHotkey() {
        #expect(KeymapCatalog.parseHotkey("CTRL--") == .init(modifiers: ["CTRL"], mainKey: "-"))
        #expect(KeymapCatalog.parseHotkey("ALT-CTRL-SHIFT-NUMPAD1") == .init(modifiers: ["ALT", "CTRL", "SHIFT"], mainKey: "NUMPAD1"))
        #expect(KeymapCatalog.parseHotkey("control-menu-F5") == .init(modifiers: ["CTRL", "ALT"], mainKey: "F5"))
        #expect(KeymapCatalog.parseHotkey("CMD-F1") == .init(modifiers: ["CMD"], mainKey: "F1"))
        #expect(KeymapCatalog.parseHotkey("COMMAND-ALT-F1") == .init(modifiers: ["CMD", "ALT"], mainKey: "F1"))
        #expect(KeymapCatalog.parseHotkey("ALT-CTRL-SHIFT-CMD-RIGHT") == .init(modifiers: ["ALT", "CTRL", "SHIFT", "CMD"], mainKey: "RIGHT"))
        #expect(KeymapCatalog.parseHotkey("CTRL-CTRL-7") == .init(modifiers: ["CTRL"], mainKey: "7"))
        #expect(KeymapCatalog.parseHotkey("SHIFT-") == .init(modifiers: ["SHIFT"], mainKey: nil))
        #expect(KeymapCatalog.parseHotkey("  ") == .init(modifiers: [], mainKey: nil))
        #expect(KeymapCatalog.parseHotkey("XBUTTON2") == .init(modifiers: [], mainKey: "XBUTTON2"))
    }

    @Test("macOS Command 与小键盘虚拟键码")
    func macKeyCodes() {
        #expect(MacKeyCodes.Modifier.cmd.keyCode == 0x37)
        #expect(MacKeyCodes.keyCode(for: "NUMPAD1") == 0x53)
        #expect(MacKeyCodes.keyCode(for: "RIGHT") == 0x7C)
    }

    @Test("三元组精确匹配、nil 走二元回退、last-wins")
    func resolution() {
        let keymap = KeymapSelection.make(entries: [
            (unit: 32, spell: "惩击", condition: "", hotkey: "CTRL-F1"),
            (unit: 32, spell: "惩击", condition: "nochanneling", hotkey: "CTRL-F2"),
            (unit: 36, spell: "引导", condition: nil, hotkey: "ALT-1"),
            (unit: 0, spell: "重复", condition: "", hotkey: "A"),
            (unit: 0, spell: "重复", condition: "", hotkey: "B")
        ])
        #expect(keymap.hotkey(unit: 32, spell: "惩击", macroCondition: "") == "CTRL-F1")
        #expect(keymap.hotkey(unit: 32, spell: "惩击", macroCondition: "nochanneling") == "CTRL-F2")
        #expect(keymap.hotkey(unit: 32, spell: "惩击", macroCondition: "非引导") == "CTRL-F2", "中文旧值归一化")
        #expect(keymap.hotkey(unit: 32, spell: "惩击", macroCondition: "channeling") == nil, "精确表无回退")
        #expect(keymap.hotkey(unit: 32, spell: "惩击", macroCondition: nil) == "CTRL-F2", "nil 走二元回退表，最后一项胜出")
        #expect(keymap.hotkey(unit: 0, spell: "引导", macroCondition: "channeling") == "ALT-1", "unit 36 迁移为 0 + channeling")
        #expect(keymap.hotkey(unit: nil, spell: "重复", macroCondition: "") == "B")
    }

    @Test("从真实文件加载：专精子表整体替换顶层")
    func loadFromFixtures() throws {
        try Fixtures.withTempDirectory { dir in
            let paths = try Fixtures.makePaths(dir)
            let config = try ConfigService.load(configDirectory: paths.configDirectory)
            let priest = KeymapSelection.load(paths: paths, config: config, classId: 5, specId: 1)
            #expect(!priest.isEmpty)
            #expect(priest.hotkey(unit: 1, spell: "纯净术", macroCondition: "") == "CTRL-NUMPAD1")
            #expect(priest.currentSpellIndices[8122] == 1)
            #expect(priest.currentSpellNames[8122] == "心灵尖啸")
            #expect(!priest.currentItemIndices.isEmpty)
            #expect(!priest.currentFailedSpells.isEmpty)
            let noSpec = KeymapSelection.load(paths: paths, config: config, classId: 5, specId: nil)
            #expect(!noSpec.isEmpty)
        }
    }

    @Test("keymap 文件路径回退")
    func resolveFile() throws {
        try Fixtures.withTempDirectory { dir in
            let keymapDir = dir.appendingPathComponent("keymap")
            try FileManager.default.createDirectory(at: keymapDir, withIntermediateDirectories: true)
            try "{}".write(to: keymapDir.appendingPathComponent("priest.json"), atomically: true, encoding: .utf8)
            #expect(KeymapCatalog.resolveKeymapFile(keymapDirectory: keymapDir, keymapName: "priest.yml").lastPathComponent == "priest.json")
            #expect(KeymapCatalog.resolveKeymapFile(keymapDirectory: keymapDir, keymapName: "missing.json").lastPathComponent == "keymap.json")
        }
    }

    @Test("编辑器目录聚合顶层与专精")
    func editorCatalog() {
        let catalog = KeymapEditorCatalog.load(Fixtures.url("keymap/priest.json"))
        #expect(catalog.spells.contains("纯净术"))
        #expect(catalog.units.first == 0 || catalog.units.first == 1)
        #expect(catalog.units(forSpell: "纯净术").contains(1))
        #expect(catalog.units(forSpell: "不存在的技能").isEmpty)
        #expect(!catalog.macroConditions(spell: "纯净术", unit: 1).isEmpty)
    }
}
