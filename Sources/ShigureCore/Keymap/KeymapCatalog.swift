import Foundation

/// 热键池：12 个修饰符组合 × 46 个主键 = 552 个宏槽位（与 Senkoh core/macro.lua 对齐）。
public enum KeymapCatalog {
    public static let modifiers: [String] = [
        "CTRL", "ALT", "SHIFT", "CMD",
        "SHIFT-CMD",
        "CTRL-SHIFT", "CTRL-CMD",
        "ALT-CTRL", "ALT-SHIFT", "ALT-CMD", "ALT-CTRL-SHIFT", "ALT-CTRL-SHIFT-CMD"
    ]

    public static let keys: [String] = [
        "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5",
        "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0",
        "NUMPADDECIMAL", "NUMPADPLUS", "NUMPADMINUS", "NUMPADMULTIPLY", "NUMPADDIVIDE",
        "F1", "F2", "F3", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        ",", ".", "/", ";", "'", "[", "]", "\\", "-", "=",
        "INSERT", "DELETE", "HOME", "END", "PAGEUP", "PAGEDOWN",
        "UP", "DOWN", "LEFT", "RIGHT"
    ]

    /// 槽位 i（1 起）的热键字符串 = macroKind[i-1]，修饰符外层、主键内层。
    public static let macroKind: [String] = {
        var list: [String] = []
        for modifier in modifiers {
            for key in keys {
                list.append("\(modifier)-\(key)")
            }
        }
        return list
    }()

    public static var macroSlotCapacity: Int { modifiers.count * keys.count }

    public struct ParsedHotkey: Sendable, Equatable {
        public let modifiers: [String] // CTRL / ALT / SHIFT / CMD，去重，按出现顺序
        public let mainKey: String?
    }

    /// 从左消费修饰前缀，剩余整段当主键。`CTRL--` 不能按 '-' 切开，否则会丢掉减号。
    public static func parseHotkey(_ hotkey: String) -> ParsedHotkey {
        if hotkey.isBlank { return ParsedHotkey(modifiers: [], mainKey: nil) }
        var remaining = hotkey.trimmed()
        var mods: [String] = []
        while let (modifier, rest) = consumeModifierPrefix(remaining) {
            remaining = rest
            if !mods.contains(modifier) { mods.append(modifier) }
        }
        return ParsedHotkey(modifiers: mods, mainKey: remaining.isEmpty ? nil : remaining)
    }

    private static func consumeModifierPrefix(_ text: String) -> (String, String)? {
        let prefixes: [(String, String)] = [
            ("CONTROL-", "CTRL"), ("CTRL-", "CTRL"),
            ("MENU-", "ALT"), ("ALT-", "ALT"),
            ("SHIFT-", "SHIFT"), ("COMMAND-", "CMD"), ("CMD-", "CMD")
        ]
        for (prefix, modifier) in prefixes {
            if let rest = text.dropPrefixIgnoringCase(prefix) {
                return (modifier, rest)
            }
        }
        return nil
    }

    /// keymap 文件路径解析：.yml 改写为 .json；绝对路径直接使用，否则相对 keymapDirectory；找不到回退 keymap.json。
    public static func resolveKeymapFile(keymapDirectory: URL, keymapName: String?) -> URL {
        var name = keymapName ?? "keymap.json"
        if name.hasSuffixIgnoringCase(".yml") {
            name = String(name.dropLast(4)) + ".json"
        }
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : keymapDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : keymapDirectory.appendingPathComponent("keymap.json")
    }
}

/// 从职业 keymap 文件构建模块编辑器可选择的技能与目标目录（聚合顶层回退与所有专精映射）。
public struct KeymapEditorCatalog: Sendable {
    public struct SpellUnitKey: Hashable, Sendable {
        public let spell: String
        public let unit: Int
    }

    /// 去重后按文件内首次出现顺序。
    public let spells: [String]
    /// 去重升序。
    public let units: [Int]
    public let unitsBySpell: [String: [Int]]
    public let macroConditions: [SpellUnitKey: [String]]

    public static let empty = KeymapEditorCatalog(spells: [], units: [], unitsBySpell: [:], macroConditions: [:])

    public func units(forSpell spell: String?) -> [Int] {
        guard let spell, !spell.isEmpty else { return units }
        return unitsBySpell[spell] ?? []
    }

    public func units(forSpells spells: [String]) -> [Int] {
        var set = Set<Int>()
        for spell in spells where !spell.isBlank {
            for unit in unitsBySpell[spell] ?? [] { set.insert(unit) }
        }
        return set.sorted()
    }

    public func macroConditions(spell: String?, unit: Int?) -> [String] {
        guard let spell, !spell.isBlank else { return [] }
        return macroConditions[SpellUnitKey(spell: spell, unit: unit ?? 0)] ?? []
    }

    public static func load(_ url: URL) -> KeymapEditorCatalog {
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? TextFile.read(url),
              let root = try? JSONParser.parseObject(text) else { return .empty }
        var spells: [String] = []
        var seenSpells = Set<String>()
        var units: [Int] = []
        var seenUnits = Set<Int>()
        var unitsBySpell: [String: [Int]] = [:]
        var macroConditions: [SpellUnitKey: [String]] = [:]

        func addMap(_ map: JSONObject) {
            for (_, node) in map.entries {
                guard case .object(let entry) = node else { continue }
                let spell = JSONHelpers.getString(entry["spell"]) ?? JSONHelpers.getString(entry["技能"])
                let hotkey = JSONHelpers.getString(entry["hotkey"]) ?? JSONHelpers.getString(entry["热键"])
                guard let spell, !spell.isBlank, let hotkey, !hotkey.isBlank else { continue }
                let rawUnit = JSONHelpers.getInt(entry["unit"]) ?? 0
                let (unit, condition) = MacroConditionText.normalizeLegacyUnit(rawUnit, JSONHelpers.getString(entry["宏条件"]))
                if seenSpells.insert(spell).inserted { spells.append(spell) }
                if seenUnits.insert(unit).inserted { units.append(unit) }
                var list = unitsBySpell[spell] ?? []
                if !list.contains(unit) { list.append(unit) }
                unitsBySpell[spell] = list
                let key = SpellUnitKey(spell: spell, unit: unit)
                var conditions = macroConditions[key] ?? []
                if !conditions.contains(condition) { conditions.append(condition) }
                macroConditions[key] = conditions
            }
        }

        addMap(root)
        if let specRoot = root.object("专精") {
            for (_, node) in specRoot.entries {
                if case .object(let specMap) = node { addMap(specMap) }
            }
        }
        units.sort()
        for key in unitsBySpell.keys { unitsBySpell[key]?.sort() }
        return KeymapEditorCatalog(spells: spells, units: units, unitsBySpell: unitsBySpell, macroConditions: macroConditions)
    }
}
