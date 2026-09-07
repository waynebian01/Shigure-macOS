import Foundation

/// 运行时热键解析器接口（供模块逻辑使用）。
public protocol KeymapResolver: Sendable {
    func hotkey(unit: Int?, spell: String, macroCondition: String?) -> String?
    func hotkey(unit: Int?, spellId: Int64, macroCondition: String?) -> String?
    var currentFailedSpells: [Int: Int64] { get }
    var currentOneKeySpells: [Int: Int64] { get }
    var currentInsertItems: [Int: Int64] { get }
    var currentSpellIndices: [Int64: Int] { get }
    var currentSpellNames: [Int64: String] { get }
    var currentItemIndices: [Int64: Int] { get }
    var currentItemNames: [Int64: String] { get }
}

/// 某职业/专精的 keymap 快照（值类型，可缓存）。
public struct KeymapSelection: KeymapResolver, Sendable {
    struct TripleKey: Hashable { let unit: Int; let spell: String; let condition: String }
    struct PairKey: Hashable { let unit: Int; let spell: String }

    public let classId: Int?
    public let specId: Int?
    var hotkeys: [TripleKey: String] = [:]
    var fallbackHotkeys: [PairKey: String] = [:]
    public private(set) var currentSpellIndices: [Int64: Int] = [:]
    public private(set) var currentSpellNames: [Int64: String] = [:]
    public private(set) var currentItemIndices: [Int64: Int] = [:]
    public private(set) var currentItemNames: [Int64: String] = [:]
    public let currentFailedSpells: [Int: Int64]
    public let currentOneKeySpells: [Int: Int64]
    public let currentInsertItems: [Int: Int64]

    public static let empty = KeymapSelection(classId: nil, specId: nil, failed: [:], oneKey: [:], insertItems: [:])

    init(classId: Int?, specId: Int?, failed: [Int: Int64], oneKey: [Int: Int64], insertItems: [Int: Int64]) {
        self.classId = classId
        self.specId = specId
        currentFailedSpells = failed
        currentOneKeySpells = oneKey
        currentInsertItems = insertItems
    }

    /// 加载：Senkoh class Lua 的 spellsList/itemsList（索引与名称）+ keymap JSON（专精子表整体替换顶层）。
    public static func load(paths: AppPaths, config: ConfigService, classId: Int?, specId: Int?) -> KeymapSelection {
        var selection = KeymapSelection(classId: classId, specId: specId,
                                        failed: config.failedSpells(classId: classId),
                                        oneKey: config.oneKeySpells(classId: classId),
                                        insertItems: config.insertItems(classId: classId))
        selection.loadSpellIndices(paths: paths, classId: classId)
        let url = KeymapCatalog.resolveKeymapFile(keymapDirectory: paths.keymapDirectory, keymapName: config.keymapName(classId: classId))
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? TextFile.read(url),
              let root = try? JSONParser.parseObject(text) else { return selection }
        selection.loadEntries(root: root, specId: specId)
        return selection
    }

    mutating func loadEntries(root: JSONObject, specId: Int?) {
        var entries = root
        if let specId, let specRoot = root.object("专精"), let specEntries = specRoot.object(String(specId)) {
            entries = specEntries
        }
        for (_, node) in entries.entries {
            guard case .object(let entry) = node else { continue }
            let rawUnit = JSONHelpers.getInt(entry["unit"]) ?? 0
            let spell = JSONHelpers.getString(entry["spell"]) ?? JSONHelpers.getString(entry["技能"])
            let hotkey = JSONHelpers.getString(entry["hotkey"]) ?? JSONHelpers.getString(entry["热键"])
            let (unit, macroCondition) = MacroConditionText.normalizeLegacyUnit(rawUnit, JSONHelpers.getString(entry["宏条件"]))
            guard let spell, !spell.isBlank, let hotkey, !hotkey.isBlank else { continue }
            hotkeys[TripleKey(unit: unit, spell: spell, condition: macroCondition)] = hotkey
            // 兼容未保存“宏条件”的旧模块：保留旧版按单位+技能查询时的最后一项行为。
            fallbackHotkeys[PairKey(unit: unit, spell: spell)] = hotkey
        }
    }

    mutating func loadSpellIndices(paths: AppPaths, classId: Int?) {
        guard let classId else { return }
        let url = paths.classLuaFile(classId: classId)
        guard let document = try? ClassBlocksStore.load(url) else { return } // 不可用时保持空映射
        for spell in document.spellsList where spell.spellId > 0 {
            if currentSpellIndices[spell.spellId] == nil { currentSpellIndices[spell.spellId] = spell.index }
            if !spell.name.isBlank, currentSpellNames[spell.spellId] == nil { currentSpellNames[spell.spellId] = spell.name.trimmed() }
        }
        for item in document.itemsList where item.itemId > 0 {
            if currentItemIndices[item.itemId] == nil { currentItemIndices[item.itemId] = item.index }
            if !item.name.isBlank, currentItemNames[item.itemId] == nil { currentItemNames[item.itemId] = item.name.trimmed() }
        }
    }

    /// 测试/离线构造。
    public static func make(entries: [(unit: Int, spell: String, condition: String?, hotkey: String)],
                            spellIndices: [Int64: Int] = [:], spellNames: [Int64: String] = [:],
                            itemIndices: [Int64: Int] = [:], itemNames: [Int64: String] = [:],
                            failed: [Int: Int64] = [:], oneKey: [Int: Int64] = [:], insertItems: [Int: Int64] = [:]) -> KeymapSelection {
        var s = KeymapSelection(classId: nil, specId: nil, failed: failed, oneKey: oneKey, insertItems: insertItems)
        for e in entries {
            let (unit, condition) = MacroConditionText.normalizeLegacyUnit(e.unit, e.condition)
            s.hotkeys[TripleKey(unit: unit, spell: e.spell, condition: condition)] = e.hotkey
            s.fallbackHotkeys[PairKey(unit: unit, spell: e.spell)] = e.hotkey
        }
        s.currentSpellIndices = spellIndices
        s.currentSpellNames = spellNames
        s.currentItemIndices = itemIndices
        s.currentItemNames = itemNames
        return s
    }

    public var isEmpty: Bool { hotkeys.isEmpty }

    /// nil 表示旧模块根本没有该字段，严格沿用升级前“单位+技能”的最后一项匹配；非 nil 精确匹配无回退。
    public func hotkey(unit: Int?, spell: String, macroCondition: String?) -> String? {
        let normalizedUnit = unit ?? 0
        guard let macroCondition else {
            return fallbackHotkeys[PairKey(unit: normalizedUnit, spell: spell)]
        }
        return hotkeys[TripleKey(unit: normalizedUnit, spell: spell, condition: MacroConditionText.normalize(macroCondition))]
    }

    public func hotkey(unit: Int?, spellId: Int64, macroCondition: String?) -> String? {
        guard let spell = currentSpellNames[spellId] else { return nil }
        return hotkey(unit: unit, spell: spell, macroCondition: macroCondition)
    }
}

/// 按 (classId, specId) 缓存 KeymapSelection；对应 C# KeymapService.SelectForClass 的记忆化。
public final class KeymapService: @unchecked Sendable {
    private let paths: AppPaths
    private let config: ConfigService
    private let lock = NSLock()
    private var current: KeymapSelection = .empty

    public init(paths: AppPaths, config: ConfigService) {
        self.paths = paths
        self.config = config
    }

    public func select(classId: Int?, specId: Int?) -> KeymapSelection {
        lock.lock()
        defer { lock.unlock() }
        if current.classId == classId, current.specId == specId, !current.isEmpty {
            return current
        }
        current = KeymapSelection.load(paths: paths, config: config, classId: classId, specId: specId)
        return current
    }
}
