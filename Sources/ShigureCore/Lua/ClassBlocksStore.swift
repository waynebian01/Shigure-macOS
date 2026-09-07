import Foundation

public struct LuaStoreError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// 读写 Senkoh class/*.lua 中的 ClassBlocks（states/auras/spells/items/group），
/// 同时读写 spellsList 与 itemsList；保存时替换 ClassBlocks 表字面量，并原位更新列表条目。
public enum ClassBlocksStore {
    public static let assignmentName = "Senkoh.ClassBlocks"
    public static let spellsListAssignmentName = "Senkoh.spellsList"
    public static let itemsListAssignmentName = "Senkoh.itemsList"
    static let stateCategories = ClassStateCatalog.topCategories

    public struct AuraEntry: Sendable, Equatable {
        public var name: String = ""
        public var spellId: Int64?
        public var spellIds: [Int64] = []
        public var maxApps: Int?
        public init(name: String = "", spellId: Int64? = nil, spellIds: [Int64] = [], maxApps: Int? = nil) {
            self.name = name; self.spellId = spellId; self.spellIds = spellIds; self.maxApps = maxApps
        }
    }

    public struct SpellEntry: Sendable, Equatable {
        public var name: String = ""
        public var spellId: Int64
        public var charge = false
        public var maxCharge: Int?
        public var castCount: Int?
        public var forcedKnown = false
        public var inSpellBook = false
        public init(name: String = "", spellId: Int64, charge: Bool = false, maxCharge: Int? = nil, castCount: Int? = nil, forcedKnown: Bool = false, inSpellBook: Bool = false) {
            self.name = name; self.spellId = spellId; self.charge = charge; self.maxCharge = maxCharge
            self.castCount = castCount; self.forcedKnown = forcedKnown; self.inSpellBook = inSpellBook
        }
    }

    public struct ItemEntry: Sendable, Equatable {
        public var itemId: Int64?
        public var name: String = ""
        public var isEquipped = false
        public init(itemId: Int64? = nil, name: String = "", isEquipped: Bool = false) {
            self.itemId = itemId; self.name = name; self.isEquipped = isEquipped
        }
    }

    public struct GroupAuraEntry: Sendable, Equatable {
        public var offset: Int
        public var name: String = ""
        public var spellId: Int64?
        public var spellIds: [Int64] = []
        public init(offset: Int, name: String = "", spellId: Int64? = nil, spellIds: [Int64] = []) {
            self.offset = offset; self.name = name; self.spellId = spellId; self.spellIds = spellIds
        }
    }

    public struct GroupBlocks: Sendable, Equatable {
        public var num = 5
        public var healthPercent: Int? = 1
        public var role: Int? = 2
        public var dispel: Int?
        public var auras: [GroupAuraEntry] = []
        public init() {}
    }

    public struct SpecBlocks: Sendable, Equatable {
        public var nestedStates = true
        public var flatStates: [String] = []
        /// 预置全部 13 个分类（空数组）。
        public var categorizedStates: [String: [String]] = Dictionary(uniqueKeysWithValues: ClassStateCatalog.topCategories.map { ($0, [String]()) })
        public var playerAuras: [AuraEntry] = []
        public var items: [ItemEntry] = []
        public var targetHarmfulAuras: [AuraEntry] = []
        public var targetHelpfulAuras: [AuraEntry] = []
        public var focusHarmfulAuras: [AuraEntry] = []
        public var focusHelpfulAuras: [AuraEntry] = []
        public var spells: [SpellEntry] = []
        public var group: GroupBlocks?
        public init() {}
    }

    public struct SpellsListEntry: Sendable, Equatable {
        public var spellId: Int64
        public var index: Int
        public var name: String
        public var originalSpellId: Int64
        public var originalIndex: Int
        public var originalName: String

        public init(spellId: Int64, index: Int, name: String) {
            self.spellId = spellId; self.index = index; self.name = name
            originalSpellId = 0; originalIndex = 0; originalName = ""
        }

        public var isNew: Bool { originalSpellId == 0 }
        var isChanged: Bool { !isNew && (spellId != originalSpellId || index != originalIndex || name != originalName) }
    }

    public struct ItemsListEntry: Sendable, Equatable {
        public var itemId: Int64
        public var index: Int
        public var name: String
        public var originalItemId: Int64
        public var originalIndex: Int
        public var originalName: String

        public init(itemId: Int64, index: Int, name: String) {
            self.itemId = itemId; self.index = index; self.name = name
            originalItemId = 0; originalIndex = 0; originalName = ""
        }

        public var isNew: Bool { originalItemId == 0 }
        var isChanged: Bool { !isNew && (itemId != originalItemId || index != originalIndex || name != originalName) }
    }

    public struct Document: Sendable {
        public var fileURL: URL
        public var sourceText: String
        public var tableStart: Int
        public var tableEndExclusive: Int
        public var specs: [Int: SpecBlocks]
        public var spellsList: [SpellsListEntry]
        public var deletedSpellsListOriginalIds: Set<Int64> = []
        public var itemsList: [ItemsListEntry]
        public var deletedItemsListOriginalIds: Set<Int64> = []
        public var isModernFormat: Bool
    }

    // MARK: Load

    public static func load(_ url: URL) throws -> Document {
        let source = try TextFile.read(url)
        return try parse(source: source, fileURL: url)
    }

    public static func parse(source: String, fileURL: URL) throws -> Document {
        guard let extracted = try LuaLiteParser.extract(source, assignmentName) else {
            throw LuaStoreError("\(fileURL.lastPathComponent) 中未找到 \(assignmentName)")
        }
        var specs: [Int: SpecBlocks] = [:]
        var modern = false
        for entry in extracted.table.entries {
            guard case .int(let specId)? = entry.key, case .table(let specTable) = entry.value else { continue }
            let (spec, specModern) = parseSpec(specTable)
            modern = modern || specModern
            specs[Int(specId)] = spec
        }
        return Document(
            fileURL: fileURL,
            sourceText: source,
            tableStart: extracted.tableStart,
            tableEndExclusive: extracted.tableEndExclusive,
            specs: specs,
            spellsList: parseSpellsList(LuaLiteParser.extractAssignedTable(source, spellsListAssignmentName)),
            itemsList: parseItemsList(LuaLiteParser.extractAssignedTable(source, itemsListAssignmentName)),
            isModernFormat: modern)
    }

    static func parseSpellsList(_ table: LuaTable?) -> [SpellsListEntry] {
        guard let table else { return [] }
        var result: [SpellsListEntry] = []
        for entry in table.entries {
            guard case .int(let spellId)? = entry.key, case .table(let spell) = entry.value else { continue }
            let indexValue = spell.number("index")
            let name = spell.string("name")?.trimmed()
            guard let indexValue, indexValue > 0, indexValue <= Double(Int32.max), indexValue == indexValue.rounded(.towardZero),
                  let name, !name.isBlank else { continue }
            var e = SpellsListEntry(spellId: spellId, index: Int(indexValue), name: name)
            e.originalSpellId = spellId
            e.originalIndex = Int(indexValue)
            e.originalName = name
            result.append(e)
        }
        return result
    }

    static func parseItemsList(_ table: LuaTable?) -> [ItemsListEntry] {
        guard let table else { return [] }
        var result: [ItemsListEntry] = []
        for entry in table.entries {
            guard case .int(let itemId)? = entry.key, itemId > 0 else { continue }
            var index = 0
            var name: String?
            switch entry.value {
            case .string(let text):
                name = text.trimmed()
            case .table(let item):
                name = item.string("name")?.trimmed()
                if let n = item.number("index"), n > 0, n <= Double(Int32.max), n == n.rounded(.towardZero) {
                    index = Int(n)
                }
            default: break
            }
            guard let name, !name.isBlank else { continue }
            var e = ItemsListEntry(itemId: itemId, index: index, name: name)
            e.originalItemId = itemId
            e.originalIndex = index
            e.originalName = name
            result.append(e)
        }
        assignMissingItemsListIndices(&result)
        return result
    }

    static func assignMissingItemsListIndices(_ entries: inout [ItemsListEntry]) {
        var used = Set(entries.filter { $0.index > 0 }.map(\.index))
        var next = 1
        for i in entries.indices where entries[i].index <= 0 {
            while used.contains(next) { next += 1 }
            entries[i].index = next
            used.insert(next)
            next += 1
        }
    }

    static func parseSpec(_ spec: LuaTable) -> (SpecBlocks, Bool) {
        var result = SpecBlocks()
        let isModern = spec.table("states") != nil || spec.table("auras") != nil || spec.table("spells") != nil
            || spec.table("items") != nil || spec.table("group") != nil
        if !isModern { return (result, false) }

        if let states = spec.table("states") {
            let nested = stateCategories.contains { states.table($0) != nil }
            result.nestedStates = nested
            if nested {
                for category in stateCategories {
                    guard let list = states.table(category) else { continue }
                    var target = result.categorizedStates[category] ?? []
                    for item in list.ipairs() {
                        if case .string(let name) = item, !name.isBlank { target.append(name) }
                    }
                    result.categorizedStates[category] = target
                }
                relocateSpecialStateFields(&result)
            } else {
                for item in states.ipairs() {
                    if case .string(let name) = item, !name.isBlank { result.flatStates.append(name) }
                }
            }
        }

        if let auras = spec.table("auras") {
            let nested = auras.table("player") != nil || auras.table("target") != nil || auras.table("focus") != nil
            if nested {
                result.playerAuras = parseAuraList(auras.table("player"))
                if let target = auras.table("target") {
                    result.targetHarmfulAuras = parseAuraList(target.table("harmful"))
                    result.targetHelpfulAuras = parseAuraList(target.table("helpful"))
                }
                if let focus = auras.table("focus") {
                    result.focusHarmfulAuras = parseAuraList(focus.table("harmful"))
                    result.focusHelpfulAuras = parseAuraList(focus.table("helpful"))
                }
            } else {
                result.playerAuras = parseAuraList(auras)
            }
        }

        if let spells = spec.table("spells") {
            for item in spells.ipairs() {
                guard case .table(let spell) = item, let spellId = spell.number("spellId") else { continue }
                result.spells.append(SpellEntry(
                    name: spell.string("name")?.trimmed() ?? "",
                    spellId: Int64(spellId.rounded(.towardZero)),
                    charge: spell.bool("charge") == true,
                    maxCharge: spell.number("maxCharge").map { Int($0.rounded(.towardZero)) },
                    castCount: spell.number("castCount").map { Int($0.rounded(.towardZero)) },
                    forcedKnown: spell.bool("forcedKnown") == true,
                    inSpellBook: spell.bool("inSpellBook") == true))
            }
        }

        if let items = spec.table("items") {
            result.items = parseItems(items)
        }

        if let group = spec.table("group") {
            var blocks = GroupBlocks()
            blocks.num = Int((group.number("num") ?? 5).rounded(.towardZero))
            blocks.healthPercent = group.number("healthPercent").map { Int($0.rounded(.towardZero)) }
            blocks.role = group.number("role").map { Int($0.rounded(.towardZero)) }
            blocks.dispel = group.number("dispel").map { Int($0.rounded(.towardZero)) }
            if let auraOffsets = group.table("aura") {
                for entry in auraOffsets.entries {
                    guard case .int(let offset)? = entry.key, case .table(let auraInfo) = entry.value else { continue }
                    var e = GroupAuraEntry(offset: Int(offset), name: auraInfo.string("name")?.trimmed() ?? "")
                    if let sid = auraInfo.number("spellId") { e.spellId = Int64(sid.rounded(.towardZero)) }
                    if let ids = auraInfo.table("spellIds") {
                        for idItem in ids.ipairs() {
                            if let n = idItem.intValue { e.spellIds.append(n) }
                        }
                    }
                    blocks.auras.append(e)
                }
                blocks.auras.sort { $0.offset < $1.offset }
            }
            result.group = blocks
        }
        return (result, true)
    }

    static func parseItems(_ list: LuaTable) -> [ItemEntry] {
        var result: [ItemEntry] = []
        var seen = Set<Int64>()
        for entry in list.entries {
            guard case .int(let itemId)? = entry.key, itemId > 0, case .table(let itemTable) = entry.value, seen.insert(itemId).inserted else { continue }
            let name = itemTable.string("name")?.trimmed() ?? ""
            if name.isBlank {
                seen.remove(itemId)
                continue
            }
            result.append(ItemEntry(itemId: itemId, name: name, isEquipped: itemTable.bool("isEquipped") == true))
        }
        result.sort { compareItemIds($0.itemId, $1.itemId) }
        return result
    }

    static func compareItemIds(_ left: Int64?, _ right: Int64?) -> Bool {
        switch (left, right) {
        case (nil, _): return false
        case (_, nil): return true
        case (let l?, let r?): return l < r
        }
    }

    static func parseAuraList(_ list: LuaTable?) -> [AuraEntry] {
        guard let list else { return [] }
        var result: [AuraEntry] = []
        for item in list.ipairs() {
            guard case .table(let aura) = item else { continue }
            var e = AuraEntry(name: aura.string("name")?.trimmed() ?? "",
                              maxApps: aura.number("maxApps").map { Int($0.rounded(.towardZero)) })
            if let sid = aura.number("spellId") { e.spellId = Int64(sid.rounded(.towardZero)) }
            if let ids = aura.table("spellIds") {
                for idItem in ids.ipairs() {
                    if let n = idItem.intValue { e.spellIds.append(n) }
                }
            }
            result.append(e)
        }
        return result
    }

    /// 嵌套格式下，把仅属于“特殊”目录的字段从“状态”移到“特殊”。
    public static func relocateSpecialStateFields(_ spec: inout SpecBlocks) {
        guard spec.nestedStates,
              var stateList = spec.categorizedStates[ClassStateCatalog.categoryState],
              var specialList = spec.categorizedStates[ClassStateCatalog.categorySpecial] else { return }
        var index = 0
        while index < stateList.count {
            let name = stateList[index]
            if !ClassStateCatalog.isKnown(category: ClassStateCatalog.categorySpecial, name: name)
                || ClassStateCatalog.isKnown(category: ClassStateCatalog.categoryState, name: name) {
                index += 1
                continue
            }
            stateList.remove(at: index)
            if !specialList.contains(name) { specialList.append(name) }
        }
        spec.categorizedStates[ClassStateCatalog.categoryState] = stateList
        spec.categorizedStates[ClassStateCatalog.categorySpecial] = specialList
    }

    // MARK: Save

    /// 写回：原位更新 spellsList/itemsList → 替换 ClassBlocks 表字面量 → 原子写 UTF-8（无 BOM）。返回更新后的文档。
    @discardableResult
    public static func save(_ document: Document) throws -> Document {
        let updatedText = try serializeDocument(document)
        try AtomicFile.write(updatedText, to: document.fileURL, withBOM: false)
        guard let relocated = try LuaLiteParser.extract(updatedText, assignmentName) else {
            throw LuaStoreError("保存后无法重新定位 ClassBlocks 表。")
        }
        var result = document
        result.sourceText = updatedText
        result.tableStart = relocated.tableStart
        result.tableEndExclusive = relocated.tableEndExclusive
        for i in result.spellsList.indices {
            result.spellsList[i].originalSpellId = result.spellsList[i].spellId
            result.spellsList[i].originalIndex = result.spellsList[i].index
            result.spellsList[i].originalName = result.spellsList[i].name
        }
        result.deletedSpellsListOriginalIds = []
        for i in result.itemsList.indices {
            result.itemsList[i].originalItemId = result.itemsList[i].itemId
            result.itemsList[i].originalIndex = result.itemsList[i].index
            result.itemsList[i].originalName = result.itemsList[i].name
        }
        result.deletedItemsListOriginalIds = []
        return result
    }

    /// 生成保存后的完整文件文本（不写盘），供测试与保存共用。
    public static func serializeDocument(_ document: Document) throws -> String {
        guard document.isModernFormat else {
            throw LuaStoreError("当前文件仍是旧版稀疏索引 ClassBlocks，无法用图形编辑器保存。")
        }
        var updated = try updateSpellsListEntries(document.sourceText, document.spellsList, document.deletedSpellsListOriginalIds)
        updated = try updateItemsListEntries(updated, document.itemsList, document.deletedItemsListOriginalIds)
        guard let located = try LuaLiteParser.extract(updated, assignmentName) else {
            throw LuaStoreError("保存前无法重新定位 ClassBlocks 表。")
        }
        let serialized = try serializeClassBlocks(document.specs)
        return LuaLiteParser.replaceRange(in: updated, start: located.tableStart, endExclusive: located.tableEndExclusive, with: serialized)
    }

    private static let spellsListLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*\[[ \t]*)(\d+)([ \t]*\][ \t]*=[ \t]*\{[ \t]*index[ \t]*=[ \t]*)(\d+)([ \t]*,[ \t]*name[ \t]*=[ \t]*)("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')([^\r\n]*)(\r?\n|$)"#,
        options: [.anchorsMatchLines])

    static func updateSpellsListEntries(_ source: String, _ entries: [SpellsListEntry], _ deletedOriginalIds: Set<Int64>) throws -> String {
        let newEntries = entries.filter(\.isNew)
        var changed: [Int64: SpellsListEntry] = [:]
        for e in entries where e.isChanged { changed[e.originalSpellId] = e }
        if changed.isEmpty && newEntries.isEmpty && deletedOriginalIds.isEmpty { return source }

        guard let located = try LuaLiteParser.extract(source, spellsListAssignmentName) else {
            throw LuaStoreError("当前文件中未找到 \(spellsListAssignmentName)，无法保存技能列表。")
        }
        let utf16 = source.utf16
        let startIdx = utf16.index(utf16.startIndex, offsetBy: located.tableStart)
        let endIdx = utf16.index(utf16.startIndex, offsetBy: located.tableEndExclusive)
        let tableText = String(utf16[startIdx..<endIdx])!

        var updatedOriginalIds = Set<Int64>()
        var deletedIdsFound = Set<Int64>()
        var updatedTable = ""
        var lastEnd = tableText.startIndex
        let ns = tableText as NSString
        for match in spellsListLineRegex.matches(in: tableText, range: NSRange(location: 0, length: ns.length)) {
            guard let whole = Range(match.range, in: tableText) else { continue }
            updatedTable += tableText[lastEnd..<whole.lowerBound]
            lastEnd = whole.upperBound
            func group(_ i: Int) -> String { Range(match.range(at: i), in: tableText).map { String(tableText[$0]) } ?? "" }
            guard let originalId = Int64(group(2)) else {
                updatedTable += tableText[whole]
                continue
            }
            if deletedOriginalIds.contains(originalId) {
                deletedIdsFound.insert(originalId)
                continue
            }
            guard let entry = changed[originalId] else {
                updatedTable += tableText[whole]
                continue
            }
            updatedOriginalIds.insert(originalId)
            let quotedName = group(6)
            let quote = quotedName.first ?? "\""
            updatedTable += group(1) + String(entry.spellId) + group(3) + String(entry.index) + group(5)
                + String(quote) + escapeLuaString(entry.name, quote: quote) + String(quote) + group(7) + group(8)
        }
        updatedTable += tableText[lastEnd...]

        let missing = changed.keys.filter { !updatedOriginalIds.contains($0) }.sorted()
        if !missing.isEmpty {
            throw LuaStoreError("无法在 \(spellsListAssignmentName) 中定位法术 ID \(missing.map(String.init).joined(separator: ", ")) 的原始条目。")
        }
        let missingDeleted = deletedOriginalIds.filter { !deletedIdsFound.contains($0) }.sorted()
        if !missingDeleted.isEmpty {
            throw LuaStoreError("无法在 \(spellsListAssignmentName) 中定位待删除的法术 ID \(missingDeleted.map(String.init).joined(separator: ", "))。")
        }

        if !newEntries.isEmpty {
            let newline = source.contains("\r\n") ? "\r\n" : "\n"
            var chars = Array(updatedTable)
            let closingBraceIndex = chars.count - 1
            let searchEnd = max(0, closingBraceIndex - 1)
            let closingLineBreak = chars[0...searchEnd].lastIndex(of: "\n")
            let insertionIndex = closingLineBreak.map { $0 + 1 } ?? closingBraceIndex
            var insertion = closingLineBreak == nil ? newline : ""
            for entry in newEntries.sorted(by: { $0.index < $1.index }) {
                insertion += "    [\(entry.spellId)] = { index = \(entry.index), name = \"\(escapeLuaString(entry.name, quote: "\""))\" },\(newline)"
            }
            chars.insert(contentsOf: Array(insertion), at: insertionIndex)
            updatedTable = String(chars)
        }

        return String(utf16[utf16.startIndex..<startIdx])! + updatedTable + String(utf16[endIdx...])!
    }

    static func updateItemsListEntries(_ source: String, _ entries: [ItemsListEntry], _ deletedOriginalIds: Set<Int64>) throws -> String {
        let newline = source.contains("\r\n") ? "\r\n" : "\n"
        guard let located = try LuaLiteParser.extract(source, itemsListAssignmentName) else {
            guard let spells = try LuaLiteParser.extract(source, spellsListAssignmentName) else {
                throw LuaStoreError("当前文件中未找到 \(spellsListAssignmentName)，无法写入物品列表。")
            }
            let insertion = newline + newline + itemsListAssignmentName + " = " + serializeItemsListTableLiteral(entries, newline: newline)
            return LuaLiteParser.replaceRange(in: source, start: spells.tableEndExclusive, endExclusive: spells.tableEndExclusive, with: insertion)
        }
        let newEntries = entries.filter(\.isNew)
        let changedCount = entries.filter(\.isChanged).count
        let utf16 = source.utf16
        let s = utf16.index(utf16.startIndex, offsetBy: located.tableStart)
        let e = utf16.index(utf16.startIndex, offsetBy: located.tableEndExclusive)
        let tableText = String(utf16[s..<e])!
        let usesIndexedObjectEntries = tableText.contains("index =")
        if changedCount == 0 && newEntries.isEmpty && deletedOriginalIds.isEmpty && (entries.isEmpty || usesIndexedObjectEntries) {
            return source
        }
        return LuaLiteParser.replaceRange(in: source, start: located.tableStart, endExclusive: located.tableEndExclusive,
                                          with: serializeItemsListTableLiteral(entries, newline: newline))
    }

    static func serializeItemsListTableLiteral(_ entries: [ItemsListEntry], newline: String) -> String {
        if entries.isEmpty { return "{}" }
        var out = "{" + newline
        for entry in entries.sorted(by: { ($0.index, $0.itemId) < ($1.index, $1.itemId) }) {
            out += "    [\(entry.itemId)] = { index = \(entry.index), name = \"\(escapeLuaString(entry.name, quote: "\""))\" },\(newline)"
        }
        out += "}"
        return out
    }

    static func escapeLuaString(_ value: String, quote: Character) -> String {
        var escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        escaped = quote == "'" ? escaped.replacingOccurrences(of: "'", with: "\\'") : escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    // MARK: 序列化 ClassBlocks

    public static func serializeClassBlocks(_ specs: [Int: SpecBlocks]) throws -> String {
        var sb = "{\n"
        for specId in specs.keys.sorted() {
            sb += "    [\(specId)] = {\n"
            try writeSpec(&sb, specs[specId]!, indent: "        ")
            sb += "    },\n"
        }
        sb += "}"
        return sb
    }

    private static func writeSpec(_ sb: inout String, _ input: SpecBlocks, indent: String) throws {
        var spec = input
        relocateSpecialStateFields(&spec)
        try validateItemsForSerialization(spec)

        sb += indent + "states = {\n"
        if spec.nestedStates {
            for category in stateCategories {
                guard let list = spec.categorizedStates[category], !list.isEmpty else { continue }
                sb += indent + "    [\"\(escape(category))\"] = {\n"
                for name in list {
                    sb += indent + "        \"\(escape(name))\",\n"
                }
                sb += indent + "    },\n"
            }
        } else {
            for name in spec.flatStates {
                sb += indent + "    \"\(escape(name))\",\n"
            }
        }
        sb += indent + "},\n"

        let hasAuras = !spec.playerAuras.isEmpty || !spec.targetHarmfulAuras.isEmpty || !spec.targetHelpfulAuras.isEmpty
            || !spec.focusHarmfulAuras.isEmpty || !spec.focusHelpfulAuras.isEmpty
        if hasAuras {
            sb += indent + "auras = {\n"
            if !spec.playerAuras.isEmpty {
                sb += indent + "    player = {\n"
                for aura in spec.playerAuras { writeAuraEntry(&sb, aura, indent: indent + "        ") }
                sb += indent + "    },\n"
            }
            writeAuraSplitUnit(&sb, "target", spec.targetHarmfulAuras, spec.targetHelpfulAuras, indent: indent + "    ")
            writeAuraSplitUnit(&sb, "focus", spec.focusHarmfulAuras, spec.focusHelpfulAuras, indent: indent + "    ")
            sb += indent + "},\n"
        }

        if !spec.spells.isEmpty {
            sb += indent + "spells = {\n"
            for spell in spec.spells {
                sb += indent + "    { spellId = \(spell.spellId)"
                if !spell.name.isBlank { sb += ", name = \"\(escape(spell.name))\"" }
                if spell.charge { sb += ", charge = true" }
                if let maxCharge = spell.maxCharge { sb += ", maxCharge = \(maxCharge)" }
                if let castCount = spell.castCount { sb += ", castCount = \(castCount)" }
                if spell.forcedKnown { sb += ", forcedKnown = true" }
                if spell.inSpellBook { sb += ", inSpellBook = true" }
                sb += " },\n"
            }
            sb += indent + "},\n"
        }

        if !spec.items.isEmpty {
            sb += indent + "items = {\n"
            for item in spec.items.sorted(by: { compareItemIds($0.itemId, $1.itemId) }) {
                guard let itemId = item.itemId, itemId > 0, !item.name.isBlank else {
                    throw LuaStoreError("物品配置包含无效的 itemId 或空名称。")
                }
                sb += indent + "    [\(itemId)] = { name = \"\(escape(item.name))\", isEquipped = \(item.isEquipped ? "true" : "false") },\n"
            }
            sb += indent + "},\n"
        }

        if let group = spec.group {
            sb += indent + "group = {\n"
            sb += indent + "    num = \(group.num),\n"
            if let hp = group.healthPercent { sb += indent + "    healthPercent = \(hp),\n" }
            if let role = group.role { sb += indent + "    role = \(role),\n" }
            if let dispel = group.dispel { sb += indent + "    dispel = \(dispel),\n" }
            if !group.auras.isEmpty {
                sb += indent + "    aura = {\n"
                for aura in group.auras.sorted(by: { $0.offset < $1.offset }) {
                    sb += indent + "        [\(aura.offset)] = {"
                    if !aura.name.isBlank { sb += " name = \"\(escape(aura.name))\"," }
                    writeSpellIdFields(&sb, aura.spellId, aura.spellIds)
                    sb += " },\n"
                }
                sb += indent + "    },\n"
            }
            sb += indent + "},\n"
        }
    }

    static func validateItemsForSerialization(_ spec: SpecBlocks) throws {
        if spec.items.isEmpty { return }
        var ids = Set<Int64>()
        var names = Set<String>()
        var bareNames = Set<String>()
        if spec.nestedStates {
            for category in [ClassStateCatalog.categoryState, ClassStateCatalog.categorySpecial, ClassStateCatalog.categoryResource, ClassStateCatalog.categoryConfig] {
                bareNames.formUnion(spec.categorizedStates[category] ?? [])
            }
        } else {
            bareNames.formUnion(spec.flatStates)
        }
        for item in spec.items {
            guard let itemId = item.itemId, itemId > 0, !item.name.isBlank else {
                throw LuaStoreError("物品配置包含无效的 itemId 或空名称。")
            }
            if !ids.insert(itemId).inserted { throw LuaStoreError("物品 itemId \(itemId) 重复。") }
            if !names.insert(item.name).inserted { throw LuaStoreError("物品名称“\(item.name)”重复。") }
            if bareNames.contains(item.name) { throw LuaStoreError("物品名称“\(item.name)”与状态、特殊、能量或配置开关字段重名。") }
        }
    }

    private static func writeAuraSplitUnit(_ sb: inout String, _ unit: String, _ harmful: [AuraEntry], _ helpful: [AuraEntry], indent: String) {
        if harmful.isEmpty && helpful.isEmpty { return }
        sb += indent + "\(unit) = {\n"
        if !harmful.isEmpty {
            sb += indent + "    harmful = {\n"
            for aura in harmful { writeAuraEntry(&sb, aura, indent: indent + "        ") }
            sb += indent + "    },\n"
        }
        if !helpful.isEmpty {
            sb += indent + "    helpful = {\n"
            for aura in helpful { writeAuraEntry(&sb, aura, indent: indent + "        ") }
            sb += indent + "    },\n"
        }
        sb += indent + "},\n"
    }

    private static func writeAuraEntry(_ sb: inout String, _ aura: AuraEntry, indent: String) {
        sb += indent + "{"
        if !aura.name.isBlank { sb += " name = \"\(escape(aura.name))\"," }
        writeSpellIdFields(&sb, aura.spellId, aura.spellIds)
        if let maxApps = aura.maxApps { sb += " maxApps = \(maxApps)," }
        sb += " },\n"
    }

    private static func writeSpellIdFields(_ sb: inout String, _ spellId: Int64?, _ spellIds: [Int64]) {
        if !spellIds.isEmpty {
            sb += " spellIds = { " + spellIds.map(String.init).joined(separator: ", ") + " },"
        } else if let id = spellId {
            sb += " spellId = \(id),"
        }
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
