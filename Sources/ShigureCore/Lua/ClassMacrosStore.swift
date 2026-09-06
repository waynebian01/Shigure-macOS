import Foundation

/// 读写 Fuyutsui core/classmacros.lua 中的 ClassMacros，保存时只替换 ClassMacros 表字面量。
public enum ClassMacrosStore {
    public static let assignmentName = "Fuyutsui.ClassMacros"
    public static let macroBodiesAssignmentName = "Fuyutsui.MacroBodies"

    static let classFileOrder = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
                                 "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"]

    public struct ArrayEntry: Sendable, Equatable {
        public var text: String
        /// Lua 同行注释。静态宏沿用注释/技能名覆盖语义；特殊宏专门用它保存手工技能名。
        public var comment: String?
        public init(text: String, comment: String? = nil) {
            self.text = text
            self.comment = comment
        }
    }

    public struct ClassMacros: Sendable, Equatable {
        /// false 表示旧式纯数组；true 表示 common + [specIndex] 分组格式。
        public var usesSpecDynamicSpells = false
        public var dynamicCommon: [String] = []
        public var dynamicBySpec: [Int: [String]] = [:]
        public var staticSpells: [ArrayEntry] = []
        public var specialSpells: [ArrayEntry] = []
        public init() {}

        public func resolveDynamicSpells(specIndex: Int?) -> [String] {
            guard usesSpecDynamicSpells, let specIndex, let specSpells = dynamicBySpec[specIndex] else {
                return dynamicCommon
            }
            return dynamicCommon + specSpells
        }
    }

    public struct Document: Sendable {
        public var fileURL: URL
        public var sourceText: String
        public var tableStart: Int
        public var tableEndExclusive: Int
        /// 键为 Lua 中的职业键（大写），保留文件原顺序于 classOrder。
        public var classes: [String: ClassMacros]
        public var classOrder: [String]

        public func macros(forClassKey key: String) -> ClassMacros? {
            if let exact = classes[key] { return exact }
            return classes.first { $0.key.equalsIgnoringCase(key) }?.value
        }

        public mutating func setMacros(_ macros: ClassMacros, forClassKey key: String) {
            if let existing = classes.keys.first(where: { $0.equalsIgnoringCase(key) }) {
                classes[existing] = macros
            } else {
                classes[key] = macros
                classOrder.append(key)
            }
        }
    }

    public static func classFileKey(classId: Int) -> String {
        ClassNames.configFileName(classId).uppercased()
    }

    public static func load(_ url: URL) throws -> Document {
        let source = try TextFile.read(url)
        return try parse(source: source, fileURL: url)
    }

    public static func parse(source: String, fileURL: URL) throws -> Document {
        guard let extracted = try LuaLiteParser.extract(source, assignmentName) else {
            throw LuaStoreError("\(fileURL.lastPathComponent) 中未找到 \(assignmentName)")
        }
        var doc = Document(fileURL: fileURL, sourceText: source, tableStart: extracted.tableStart,
                           tableEndExclusive: extracted.tableEndExclusive, classes: [:], classOrder: [])
        for entry in extracted.table.entries {
            guard case .string(let classFile)? = entry.key, case .table(let classTable) = entry.value else { continue }
            doc.classes[classFile] = parseClass(classTable)
            doc.classOrder.append(classFile)
        }
        return doc
    }

    public static func loadMacroBodies(_ url: URL) -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path), let source = try? TextFile.read(url),
              let table = LuaLiteParser.extractAssignedTable(source, macroBodiesAssignmentName) else { return [:] }
        var result: [String: String] = [:]
        for entry in table.entries {
            guard case .string(let name)? = entry.key, !name.isBlank, case .string(let text) = entry.value, !text.isBlank else { continue }
            let key = name.trimmed()
            if result[key] == nil { result[key] = text }
        }
        return result
    }

    @discardableResult
    public static func save(_ document: Document) throws -> Document {
        let serialized = serializeClassMacros(document)
        let updated = LuaLiteParser.replaceRange(in: document.sourceText, start: document.tableStart, endExclusive: document.tableEndExclusive, with: serialized)
        try AtomicFile.write(updated, to: document.fileURL, withBOM: false)
        guard let relocated = try LuaLiteParser.extract(updated, assignmentName) else {
            throw LuaStoreError("保存后无法重新定位 ClassMacros 表。")
        }
        var result = document
        result.sourceText = updated
        result.tableStart = relocated.tableStart
        result.tableEndExclusive = relocated.tableEndExclusive
        return result
    }

    static func parseClass(_ classTable: LuaTable) -> ClassMacros {
        var macros = ClassMacros()
        if let dynamic = classTable.table("dynamicSpells") {
            var specIndexes = Set<Int>()
            for entry in dynamic.entries {
                guard case .int(let n)? = entry.key, n > 0, n <= Int64(Int32.max), dynamic.table(n) != nil else { continue }
                specIndexes.insert(Int(n))
            }
            macros.usesSpecDynamicSpells = dynamic.table("common") != nil || !specIndexes.isEmpty
            if macros.usesSpecDynamicSpells {
                macros.dynamicCommon = readStringArray(dynamic.table("common"))
                for specIndex in specIndexes.sorted() {
                    macros.dynamicBySpec[specIndex] = readStringArray(dynamic.table(Int64(specIndex)))
                }
            } else {
                macros.dynamicCommon = readStringArray(dynamic)
            }
        }
        macros.staticSpells = readArray(classTable.table("staticSpells"))
        macros.specialSpells = readArray(classTable.table("specialSpells"))
        return macros
    }

    static func readArray(_ table: LuaTable?) -> [ArrayEntry] {
        guard let table else { return [] }
        var result: [ArrayEntry] = []
        var index: Int64 = 1
        for value in table.ipairs() {
            guard case .string(let text) = value else { break }
            result.append(ArrayEntry(text: text, comment: table.trailingComment(index)))
            index += 1
        }
        return result
    }

    static func readStringArray(_ table: LuaTable?) -> [String] {
        guard let table else { return [] }
        var result: [String] = []
        for value in table.ipairs() {
            guard case .string(let text) = value else { break }
            result.append(text)
        }
        return result
    }

    public static func serializeClassMacros(_ document: Document) -> String {
        var sb = "{\n"
        var written = Set<String>()
        let order = document.classOrder.isEmpty ? classFileOrder : document.classOrder
        for classFile in order {
            guard let macros = document.macros(forClassKey: classFile) else { continue }
            written.insert(classFile.uppercased())
            writeClass(&sb, classFile, macros)
        }
        for key in document.classes.keys.sorted() where !written.contains(key.uppercased()) {
            writeClass(&sb, key, document.classes[key]!)
        }
        sb += "}"
        return sb
    }

    private static func writeClass(_ sb: inout String, _ classFile: String, _ macros: ClassMacros) {
        sb += "    \(classFile) = {\n"
        if !macros.usesSpecDynamicSpells {
            writeInlineStringArray(&sb, prefix: "        dynamicSpells = ", macros.dynamicCommon)
        } else {
            sb += "        dynamicSpells = {\n"
            writeInlineStringArray(&sb, prefix: "            common = ", macros.dynamicCommon)
            for specIndex in macros.dynamicBySpec.keys.sorted() {
                writeInlineStringArray(&sb, prefix: "            [\(specIndex)] = ", macros.dynamicBySpec[specIndex]!)
            }
            sb += "        },\n"
        }
        writeArrayTable(&sb, "staticSpells", macros.staticSpells)
        writeArrayTable(&sb, "specialSpells", macros.specialSpells)
        sb += "    },\n\n"
    }

    private static func writeInlineStringArray(_ sb: inout String, prefix: String, _ values: [String]) {
        sb += prefix
        if values.isEmpty {
            sb += "{},\n"
            return
        }
        sb += "{ " + values.map { "\"\(escape($0))\"" }.joined(separator: ", ") + " },\n"
    }

    private static func writeArrayTable(_ sb: inout String, _ name: String, _ entries: [ArrayEntry]) {
        if entries.isEmpty {
            sb += "        \(name) = {},\n"
            return
        }
        sb += "        \(name) = {\n"
        for entry in entries {
            sb += "            \"\(escape(entry.text))\""
            if let comment = entry.comment, !comment.isBlank {
                sb += ", -- \(comment.trimmed())"
            } else {
                sb += ","
            }
            sb += "\n"
        }
        sb += "        },\n"
    }

    static func escape(_ value: String) -> String {
        var out = ""
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }
}
