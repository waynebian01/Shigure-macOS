import Foundation

/// 将 Senkoh core/classmacros.lua 的 ClassMacros 展开为 keymap/*.json
/// （对齐 core/macro.lua CreateMacro 的槽位与热键池）。
public enum SenkohKeymapConverter {
    public struct UpdateResult: Sendable {
        public let classMacrosPath: URL
        public let updatedFiles: [URL]
        public let warnings: [String]
    }

    public struct ParsedMacro: Sendable, Equatable {
        public let unit: Int
        public let spell: String
        public let condition: String
    }

    public struct MacroEntry: Sendable, Equatable {
        public let body: String
        public let comment: String?
        public init(body: String, comment: String?) {
            self.body = body
            self.comment = comment
        }
    }

    /// Lua 中的职业键（大写）→ classId。
    public static let classFileToId: [(String, Int)] = [
        ("WARRIOR", 1), ("PALADIN", 2), ("HUNTER", 3), ("ROGUE", 4), ("PRIEST", 5), ("DEATHKNIGHT", 6),
        ("SHAMAN", 7), ("MAGE", 8), ("WARLOCK", 9), ("MONK", 10), ("DRUID", 11), ("DEMONHUNTER", 12), ("EVOKER", 13)
    ]

    public static func updateFromClassMacros(_ classMacrosURL: URL, keymapDirectory: URL) throws -> UpdateResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: classMacrosURL.path) else {
            throw ConvertError("找不到 classmacros.lua: \(classMacrosURL.path)")
        }
        try fm.createDirectory(at: keymapDirectory, withIntermediateDirectories: true)
        let lua = try TextFile.read(classMacrosURL)
        guard let classMacros = LuaLiteParser.extractAssignedTable(lua, "Senkoh.ClassMacros") else {
            throw ConvertError("classmacros.lua 中未找到 Senkoh.ClassMacros")
        }

        var updated: [URL] = []
        var warnings: [String] = []
        for (classFile, classId) in classFileToId {
            guard let classTable = classMacros.table(classFile) else {
                warnings.append("跳过 \(classFile): ClassMacros 中无此职业表")
                continue
            }
            let fileName = ClassNames.configFileName(classId).lowercased() + ".json"
            let jsonURL = keymapDirectory.appendingPathComponent(fileName)
            let existing = loadExistingSpellNames(jsonURL)
            let (root, classWarnings) = compileClassKeymap(classTable, existing: existing, classFile: classFile, classId: classId)
            warnings.append(contentsOf: classWarnings)
            try AtomicFile.write(JSONWriter.indented(.object(root)) + "\n", to: jsonURL, withBOM: true)
            updated.append(jsonURL)
        }
        if updated.isEmpty {
            throw ConvertError("未成功转换任何职业 keymap。")
        }
        return UpdateResult(classMacrosPath: classMacrosURL, updatedFiles: updated, warnings: warnings)
    }

    public static func compileClassKeymap(_ classTable: LuaTable, existing: ExistingSpellNames, classFile: String, classId: Int) -> (JSONObject, [String]) {
        var warnings: [String] = []
        let dynamicTable = classTable.table("dynamicSpells")
        let staticSpells = readArrayEntries(classTable.table("staticSpells"))
        let specialSpells = readArrayEntries(classTable.table("specialSpells"))

        if !isSpecializedDynamicFormat(dynamicTable) {
            let dynamicSpells = readArrayStrings(dynamicTable)
            let root = compileSlotMap(dynamicSpells, staticSpells, specialSpells, existing, specId: nil, context: classFile, warnings: &warnings)
            return (root, warnings)
        }

        let commonSpells = readArrayStrings(dynamicTable?.table("common"))
        var root = compileSlotMap(commonSpells, staticSpells, specialSpells, existing, specId: nil, context: "\(classFile)[兼容回退]", warnings: &warnings)
        var specRoot = JSONObject()
        let specs = ClassNames.specs(of: classId)
        let knownSpecIds = Set(specs.map(\.id))
        for unknown in dynamicSpecIndexes(dynamicTable) where !knownSpecIds.contains(unknown) {
            warnings.append("\(classFile)[专精 \(unknown)]: ClassNames 未登记，未生成此专精映射")
        }
        for spec in specs {
            var dynamicSpells = commonSpells
            dynamicSpells.append(contentsOf: readArrayStrings(dynamicTable?.table(Int64(spec.id))))
            specRoot[String(spec.id)] = .object(compileSlotMap(dynamicSpells, staticSpells, specialSpells, existing, specId: spec.id, context: "\(classFile)[专精 \(spec.id) \(spec.name)]", warnings: &warnings))
        }
        root["专精"] = .object(specRoot)
        return (root, warnings)
    }

    static func compileSlotMap(_ dynamicSpells: [String], _ staticSpells: [MacroEntry], _ specialSpells: [MacroEntry], _ existing: ExistingSpellNames, specId: Int?, context: String, warnings: inout [String]) -> JSONObject {
        let macroKind = KeymapCatalog.macroKind
        let dynamicSlots = dynamicSpells.count * 30
        let requiredSlots = dynamicSpells.count * 30 + staticSpells.count + specialSpells.count
        if requiredSlots > macroKind.count {
            warnings.append("\(context): 槽位容量溢出，需要 \(requiredSlots) 个，最多 \(macroKind.count) 个；末尾 \(requiredSlots - macroKind.count) 个槽位不会写入 keymap")
        }

        var root = JSONObject()
        for i in 1...macroKind.count {
            let hotkey = macroKind[i - 1]
            var unit = 0
            var spell = ""
            var macroCondition = ""

            if i <= dynamicSlots {
                let groupIndex = (i - 1) / 30
                let raidIdx = ((i - 1) % 30) + 1
                if groupIndex < dynamicSpells.count, !dynamicSpells[groupIndex].isBlank {
                    spell = dynamicSpells[groupIndex]
                    unit = raidIdx
                }
            } else {
                let relativeIndex = i - dynamicSlots - 1
                var entry: MacroEntry?
                var isStaticEntry = false
                if relativeIndex < staticSpells.count {
                    entry = staticSpells[relativeIndex]
                    isStaticEntry = true
                } else {
                    let specialIndex = relativeIndex - staticSpells.count
                    if specialIndex < specialSpells.count {
                        entry = specialSpells[specialIndex]
                    }
                }
                if let macroEntry = entry, !macroEntry.body.isEmpty {
                    let parsed = isStaticEntry
                        ? parseStaticMacro(macroEntry.body, comment: macroEntry.comment)
                        : parseSpecialMacro(macroEntry.body, comment: macroEntry.comment)
                    unit = parsed.unit
                    spell = parsed.spell
                    macroCondition = parsed.condition
                }
                if isStaticEntry, let macroEntry = entry, !macroEntry.body.isEmpty, isWeakSpellName(spell),
                   let preserved = existing.spellName(specId: specId, slot: i), !preserved.isBlank, !isWeakSpellName(preserved) {
                    warnings.append("\(context)[\(i)]: 保留原技能名「\(preserved)」（宏推导为「\(spell)」）")
                    spell = preserved
                }
            }

            var slot = JSONObject()
            slot["unit"] = .int(Int64(unit))
            slot["宏条件"] = .string(macroCondition)
            slot["技能"] = .string(spell)
            slot["热键"] = .string(hotkey)
            root[String(i)] = .object(slot)
        }
        return root
    }

    static func isSpecializedDynamicFormat(_ dynamicTable: LuaTable?) -> Bool {
        guard let dynamicTable else { return false }
        return dynamicTable.table("common") != nil || !dynamicSpecIndexes(dynamicTable).isEmpty
    }

    static func dynamicSpecIndexes(_ table: LuaTable?) -> [Int] {
        guard let table else { return [] }
        var set = Set<Int>()
        for entry in table.entries {
            guard case .table = entry.value, case .int(let value)? = entry.key, value > 0, value <= Int64(Int32.max) else { continue }
            set.insert(Int(value))
        }
        return set.sorted()
    }

    public static func isWeakSpellName(_ spell: String?) -> Bool {
        guard let spell, !spell.isBlank else { return true }
        return spell.hasPrefixIgnoringCase("item:")
    }

    // MARK: 宏解析

    private static let stopCastingRegex = try! NSRegularExpression(pattern: #"^\s*/stopcasting\b"#, options: [.caseInsensitive])
    private static let castSequenceRegex = try! NSRegularExpression(pattern: #"^\s*/castsequence\b\s*(.*)$"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let resetOptionRegex = try! NSRegularExpression(pattern: #"\breset\s*=\s*\S+\s*"#, options: [.caseInsensitive])
    private static let conditionRegex = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    private static let staticTargetRegex = try! NSRegularExpression(pattern: #"\[[^\]]*@(cursor|target|focus|player|mouseover|party[1-4]|raid(?:[1-9]|[12][0-9]|30))\b[^\]]*\]"#, options: [.caseInsensitive])

    /// 解析静态宏供 keymap 与宏列表共用。只有方括号内以 @ 开头的项属于目标。
    public static func parseStaticMacro(_ raw: String, comment: String? = nil) -> ParsedMacro {
        var unit = ReservedUnit.none
        let range = NSRange(raw.startIndex..., in: raw)
        if let match = staticTargetRegex.firstMatch(in: raw, range: range), let unitRange = Range(match.range(at: 1), in: raw) {
            unit = resolveUnitName(String(raw[unitRange]))
        }
        return ParsedMacro(unit: unit, spell: resolveSpellName(MacroEntry(body: raw, comment: comment)), condition: resolveConditions(raw))
    }

    /// 特殊宏不解析宏正文。技能名由编辑器手工填写并保存在同行注释中，固定无目标、无宏条件。
    public static func parseSpecialMacro(_ raw: String, comment: String? = nil) -> ParsedMacro {
        ParsedMacro(unit: ReservedUnit.none, spell: comment?.trimmed() ?? "", condition: "")
    }

    /// 方括号中以 @ 开头的是目标，其余逗号分隔项作为只读条件摘要。
    static func resolveConditions(_ raw: String) -> String {
        var conditions: [String] = []
        let range = NSRange(raw.startIndex..., in: raw)
        for match in conditionRegex.matches(in: raw, range: range) {
            guard let r = Range(match.range, in: raw) else { continue }
            let bracket = String(raw[r])
            guard bracket.count >= 2 else { continue }
            let inner = String(bracket.dropFirst().dropLast())
            for item in inner.split(separator: ",") {
                let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedItem.isEmpty || trimmedItem.hasPrefix("@") { continue }
                conditions.append(trimmedItem)
            }
        }
        return MacroConditionText.normalize(conditions.joined(separator: ", "))
    }

    static func resolveUnitName(_ raw: String) -> Int {
        var normalized = raw.trimmed()
        while normalized.hasPrefix("@") { normalized.removeFirst() }
        normalized = normalized.lowercased()
        if normalized.hasPrefix("party"), let idx = Int(normalized.dropFirst(5)), (1...4).contains(idx) {
            return idx + 1 // Senkoh 队伍槽位：player=1，party1..4=2..5
        }
        if normalized.hasPrefix("raid"), let idx = Int(normalized.dropFirst(4)), (1...30).contains(idx) {
            return idx
        }
        switch normalized {
        case "player", "玩家", "31": return ReservedUnit.player
        case "target", "目标", "32": return ReservedUnit.target
        case "focus", "焦点", "33": return ReservedUnit.focus
        case "cursor", "地面", "34": return ReservedUnit.cursor
        case "mouseover", "鼠标", "35": return ReservedUnit.mouseover
        default: return ReservedUnit.none
        }
    }

    static func resolveSpellName(_ entry: MacroEntry) -> String {
        if let comment = entry.comment, !comment.isBlank { return comment.trimmed() }
        return deriveSpellName(entry.body)
    }

    public static func deriveSpellName(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").trimmed()
        if text.isEmpty { return "" }

        if stopCastingRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return "停止施法"
        }

        if let match = castSequenceRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let bodyRange = Range(match.range(at: 1), in: text) {
            var sequenceBody = String(text[bodyRange]).trimmed()
            sequenceBody = resetOptionRegex.stringByReplacingMatches(in: sequenceBody, range: NSRange(sequenceBody.startIndex..., in: sequenceBody), withTemplate: "").trimmed()
            for rawPart in splitTopLevel(sequenceBody, separator: ",") {
                let part = rawPart.trimmed()
                if part.isEmpty { continue }
                if part.equalsIgnoringCase("x") { continue }
                return stripConditions(part)
            }
        }

        // cancelaura 后再 /cast：取最后一个 /cast 段；纯物品宏保留首行 item:
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let first = lines.first, first.hasPrefixIgnoringCase("item:") {
            return first.trimmed()
        }
        var i = lines.count - 1
        while i >= 0 {
            let line = lines[i]
            if line.hasPrefixIgnoringCase("/cast"), !line.hasPrefixIgnoringCase("/castsequence") {
                text = String(line.dropFirst("/cast".count)).trimmingLeadingWhitespace()
                break
            }
            if i == 0, !line.hasPrefix("/") {
                text = line
            }
            i -= 1
        }
        if text.hasPrefixIgnoringCase("/cast"), !text.hasPrefixIgnoringCase("/castsequence") {
            text = String(text.dropFirst("/cast".count)).trimmingLeadingWhitespace()
        }

        // 取 ; 分支中第一段（专精/条件分支）
        let firstBranch = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map { String($0).trimmed() } ?? ""
        let spell = stripConditions(firstBranch)
        return spell.isBlank ? "" : spell
    }

    /// 按顶层分隔符切分，方括号内的逗号不作为技能分隔符。
    static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var result: [String] = []
        var depth = 0
        var current = ""
        for ch in text {
            if ch == "[" { depth += 1 }
            else if ch == "]" && depth > 0 { depth -= 1 }
            else if ch == separator && depth == 0 {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        result.append(current)
        return result
    }

    static func stripConditions(_ text: String) -> String {
        conditionRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "").trimmed()
    }

    static func readArrayStrings(_ table: LuaTable?) -> [String] {
        guard let table else { return [] }
        var result: [String] = []
        for item in table.ipairs() {
            guard case .string(let s) = item else { break }
            result.append(s.trimmed())
        }
        return result
    }

    static func readArrayEntries(_ table: LuaTable?) -> [MacroEntry] {
        guard let table else { return [] }
        var result: [MacroEntry] = []
        var index: Int64 = 1
        for value in table.ipairs() {
            guard case .string(let s) = value else { break }
            result.append(MacroEntry(body: s, comment: table.trailingComment(index)))
            index += 1
        }
        return result
    }

    // MARK: 现有 keymap 中的技能名（弱名称保留）

    public struct ExistingSpellNames: Sendable {
        public let fallback: [Int: String]
        public let bySpec: [Int: [Int: String]]
        public static let empty = ExistingSpellNames(fallback: [:], bySpec: [:])

        func spellName(specId: Int?, slot: Int) -> String? {
            if let specId, let names = bySpec[specId], let spell = names[slot], !spell.isBlank, !SenkohKeymapConverter.isWeakSpellName(spell) {
                return spell
            }
            return fallback[slot]
        }
    }

    public static func loadExistingSpellNames(_ jsonURL: URL) -> ExistingSpellNames {
        guard FileManager.default.fileExists(atPath: jsonURL.path),
              let text = try? TextFile.read(jsonURL),
              let root = try? JSONParser.parseObject(text) else { return .empty }
        let fallback = readExistingSpellNames(root)
        var bySpec: [Int: [Int: String]] = [:]
        if let specRoot = root.object("专精") {
            for (key, node) in specRoot.entries {
                guard let specId = Int(key), case .object(let map) = node else { continue }
                bySpec[specId] = readExistingSpellNames(map)
            }
        }
        return ExistingSpellNames(fallback: fallback, bySpec: bySpec)
    }

    private static func readExistingSpellNames(_ map: JSONObject) -> [Int: String] {
        var result: [Int: String] = [:]
        for (key, node) in map.entries {
            guard let id = Int(key), case .object(let entry) = node else { continue }
            let spell = JSONHelpers.getString(entry["技能"]) ?? JSONHelpers.getString(entry["spell"])
            if let spell, !spell.isBlank { result[id] = spell }
        }
        return result
    }
}

public extension String {
    func trimmingLeadingWhitespace() -> String {
        String(drop(while: \.isWhitespace))
    }
}
