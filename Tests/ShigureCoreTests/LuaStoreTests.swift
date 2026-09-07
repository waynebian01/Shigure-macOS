import Foundation
import Testing
@testable import ShigureCore

@Suite("Lua 解析与 round-trip")
struct LuaStoreTests {
    @Test("解析全部职业 Lua 并识别为现代格式", arguments: ClassNames.allClasses.map(\.id))
    func parsesAllClassFiles(classId: Int) throws {
        let fileName = ClassNames.configFileName(classId)
        let url = Fixtures.url("Senkoh/class/\(fileName).lua")
        let doc = try ClassBlocksStore.load(url)
        #expect(doc.isModernFormat)
        #expect(!doc.specs.isEmpty)
        #expect(!doc.spellsList.isEmpty)
    }

    @Test("无改动保存只影响 ClassBlocks 表字面量，其余文本逐字节保留")
    func saveKeepsSurroundingText() throws {
        let url = Fixtures.url("Senkoh/class/Priest.lua")
        let doc = try ClassBlocksStore.load(url)
        let updated = try ClassBlocksStore.serializeDocument(doc)
        let source = doc.sourceText
        let prefix = String(source.utf16.prefix(doc.tableStart))!
        let suffix = String(source.utf16.suffix(source.utf16.count - doc.tableEndExclusive))!
        #expect(updated.hasPrefix(prefix))
        #expect(updated.hasSuffix(suffix))
        // 再次解析结果应与原文档等价（规范化 round-trip）。
        let reparsed = try ClassBlocksStore.parse(source: updated, fileURL: url)
        #expect(reparsed.specs == doc.specs)
        #expect(reparsed.spellsList.map { "\($0.spellId)/\($0.index)/\($0.name)" } == doc.spellsList.map { "\($0.spellId)/\($0.index)/\($0.name)" })
        // 规范化序列化是幂等的。
        #expect(try ClassBlocksStore.serializeDocument(reparsed) == updated)
    }

    @Test("spellsList 原位改名、删除、新增")
    func spellsListSurgicalEdit() throws {
        let url = Fixtures.url("Senkoh/class/Priest.lua")
        var doc = try ClassBlocksStore.load(url)
        let first = doc.spellsList[0]
        doc.spellsList[0].name = "改名测试"
        let removed = doc.spellsList.remove(at: 1)
        doc.deletedSpellsListOriginalIds.insert(removed.originalSpellId)
        doc.spellsList.append(ClassBlocksStore.SpellsListEntry(spellId: 999999, index: 250, name: "新法术"))
        let updated = try ClassBlocksStore.serializeDocument(doc)
        let reparsed = try ClassBlocksStore.parse(source: updated, fileURL: url)
        #expect(reparsed.spellsList.first { $0.spellId == first.spellId }?.name == "改名测试")
        #expect(!reparsed.spellsList.contains { $0.spellId == removed.spellId })
        #expect(reparsed.spellsList.contains { $0.spellId == 999999 && $0.index == 250 && $0.name == "新法术" })
        #expect(updated.contains("[999999] = { index = 250, name = \"新法术\" },"))
    }

    @Test("ClassMacros 解析与序列化 round-trip")
    func classMacrosRoundTrip() throws {
        let url = Fixtures.url("Senkoh/core/classmacros.lua")
        let doc = try ClassMacrosStore.load(url)
        #expect(doc.classOrder.count == 13)
        let paladin = try #require(doc.macros(forClassKey: "PALADIN"))
        #expect(paladin.usesSpecDynamicSpells)
        #expect(paladin.dynamicCommon.contains("清毒术"))
        let serialized = ClassMacrosStore.serializeClassMacros(doc)
        let updated = LuaLiteParser.replaceRange(in: doc.sourceText, start: doc.tableStart, endExclusive: doc.tableEndExclusive, with: serialized)
        let reparsed = try ClassMacrosStore.parse(source: updated, fileURL: url)
        #expect(reparsed.classes == doc.classes)
        #expect(reparsed.classOrder == doc.classOrder)
        #expect(ClassMacrosStore.serializeClassMacros(reparsed) == serialized)
        // MacroBodies 表保持不变
        #expect(ClassMacrosStore.loadMacroBodies(url).isEmpty == false)
    }

    @Test("行尾注释捕获")
    func trailingComments() throws {
        // 位置项 `"b" -- 注释`（逗号在下一行）：与 C# 相同，peek 阶段的 SkipTrivia 会吃掉注释，因此为 nil；
        // 带键项 `[37] = "…" -- 注释` 则可捕获。
        let lua = """
        X = {
            "a", -- 名称A
            "b" -- 名称B
            ,
            "c",
            --[[ block ]] "d", -- 名称D
            [37] = "e" -- 名称E
            ,
            [38] = "f", -- 名称F
        }
        """
        let table = try #require(LuaLiteParser.extractAssignedTable(lua, "X"))
        #expect(table.ipairs().count == 4)
        #expect(table.trailingComment(1) == "名称A")
        #expect(table.trailingComment(2) == nil)
        #expect(table.trailingComment(3) == nil)
        #expect(table.trailingComment(4) == "名称D")
        #expect(table.trailingComment(37) == "名称E")
        #expect(table.trailingComment(38) == "名称F")
    }

    @Test("字符串转义、数字与标识符")
    func literals() throws {
        let lua = #"T = { name = "a\"b\n", [37] = 'x\'y', n = -1.5e2, flag = true, none = nil, ident = SomeIdent, 3 }"#
        let table = try #require(LuaLiteParser.extractAssignedTable(lua, "T"))
        #expect(table.string("name") == "a\"b\n")
        #expect(table.get(37)?.stringValue == "x'y")
        #expect(table.number("n") == -150)
        #expect(table.bool("flag") == true)
        #expect(table.get("none") == .null)
        #expect(table.string("ident") == "SomeIdent")
        #expect(table.get(1)?.numberValue == 3)
    }
}
