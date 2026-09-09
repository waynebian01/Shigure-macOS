import Foundation

/// 模块 JSON 编解码。键名、顺序与 C# System.Text.Json（PascalCase 属性、WhenWritingNull、枚举字符串）一致，
/// 以便与 Windows 版共享模块文件。
public enum ModuleJSON {
    public struct DecodeError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    // MARK: Decode

    public static func decode(text: String) throws -> ModuleDefinition {
        let root = try JSONParser.parseObject(text)
        return decode(root)
    }

    public static func decode(_ o: JSONObject) -> ModuleDefinition {
        var m = ModuleDefinition()
        m.id = string(o["Id"]) ?? ""
        m.name = string(o["Name"]) ?? "新模块"
        m.author = string(o["Author"]) ?? ""
        m.recommendedTalent = string(o["RecommendedTalent"]) ?? ""
        m.version = string(o["Version"]) ?? ""
        m.unitMappingVersion = JSONHelpers.getInt(o["UnitMappingVersion"])
        m.enabled = JSONHelpers.getBool(o["Enabled"]) ?? true
        if let match = o.object("Match") { m.match = decodeMatch(match) }
        m.units = (o.array("Units") ?? []).compactMap { $0.objectValue.map(decodeUnit) }
        m.counts = (o.array("Counts") ?? []).compactMap { $0.objectValue.map(decodeCount) }
        m.valueAdjustments = (o.array("ValueAdjustments") ?? []).compactMap { $0.objectValue.map(decodeAdjustment) }
        m.rules = (o.array("Rules") ?? []).compactMap { $0.objectValue.map(decodeRule) }
        if let deps = o.object("Dependencies") { m.dependencies = decodeDependencies(deps) }
        return m
    }

    static func decodeMatch(_ o: JSONObject) -> ModuleMatch {
        ModuleMatch(classId: JSONHelpers.getInt(o["ClassId"]), specId: JSONHelpers.getInt(o["SpecId"]),
                    partyType: string(o["PartyType"]), heroTalent: JSONHelpers.getInt(o["HeroTalent"]))
    }

    static func decodeRule(_ o: JSONObject) -> ModuleRule {
        var r = ModuleRule()
        r.enabled = JSONHelpers.getBool(o["Enabled"]) ?? true
        r.condition = string(o["Condition"]) ?? ""
        r.comment = string(o["Comment"]) ?? ""
        r.delayMs = JSONHelpers.getInt(o["DelayMs"])
        r.logicDelayMs = JSONHelpers.getInt(o["LogicDelayMs"])
        r.continueLogic = JSONHelpers.getBool(o["ContinueLogic"])
        r.unit = JSONHelpers.getInt(o["Unit"])
        r.unitName = string(o["UnitName"])
        r.spell = string(o["Spell"]) ?? ""
        r.macroCondition = string(o["MacroCondition"])
        r.hotkey = string(o["Hotkey"]) ?? ""
        r.step = string(o["Step"]) ?? ""
        if let subs = o.array("SubConditions") {
            r.subConditions = subs.compactMap { string($0) }
        }
        return r
    }

    static func decodeUnit(_ o: JSONObject) -> ModuleUnit {
        var u = ModuleUnit()
        u.name = string(o["Name"]) ?? ""
        u.healthName = string(o["HealthName"])
        u.kind = string(o["Kind"]).flatMap(UnitSelectorKind.init(rawValue:)) ?? .lowestHealth
        u.healthThreshold = JSONHelpers.getInt(o["HealthThreshold"])
        u.healthThresholdField = string(o["HealthThresholdField"])
        u.roleFilter = string(o["RoleFilter"]).flatMap(UnitRoleFilterKind.init(rawValue:))
        u.role = JSONHelpers.getInt(o["Role"])
        u.reverse = JSONHelpers.getBool(o["Reverse"]) ?? false
        u.auraSpellIds = o.array("AuraSpellIds").map { $0.compactMap(JSONHelpers.getLong) }
        u.auraNames = o.array("AuraNames").map { $0.compactMap(string) }
        u.auraCount = JSONHelpers.getInt(o["AuraCount"])
        u.dispelType = JSONHelpers.getInt(o["DispelType"])
        return u
    }

    static func decodeCount(_ o: JSONObject) -> ModuleCountField {
        var c = ModuleCountField()
        c.name = string(o["Name"]) ?? ""
        c.kind = string(o["Kind"]).flatMap(CountKind.init(rawValue:)) ?? .unitsBelowHealth
        c.healthThreshold = JSONHelpers.getInt(o["HealthThreshold"])
        c.healthThresholdField = string(o["HealthThresholdField"])
        c.auraSpellId = JSONHelpers.getLong(o["AuraSpellId"])
        c.auraName = string(o["AuraName"])
        c.roleFilter = string(o["RoleFilter"]).flatMap(UnitRoleFilterKind.init(rawValue:))
        c.role = JSONHelpers.getInt(o["Role"])
        return c
    }

    static func decodeAdjustment(_ o: JSONObject) -> ModuleValueAdjustment {
        var a = ModuleValueAdjustment()
        a.enabled = JSONHelpers.getBool(o["Enabled"]) ?? true
        a.condition = string(o["Condition"]) ?? ""
        a.field = string(o["Field"]) ?? ""
        a.delta = JSONHelpers.getInt(o["Delta"]) ?? 0
        a.formula = string(o["Formula"]) ?? ""
        return a
    }

    static func decodeDependencies(_ o: JSONObject) -> ModuleDependencySnapshot {
        var d = ModuleDependencySnapshot()
        d.schemaVersion = JSONHelpers.getInt(o["SchemaVersion"]) ?? ModuleDependencySnapshot.currentSchemaVersion
        d.classId = JSONHelpers.getInt(o["ClassId"]) ?? 0
        d.specId = JSONHelpers.getInt(o["SpecId"]) ?? 0
        if let config = o.object("Config") {
            if let spec = config.object("Spec") { d.config.spec = decodeSpecSnapshot(spec) }
            d.config.spellsList = (config.array("SpellsList") ?? []).compactMap { node in
                guard let e = node.objectValue else { return nil }
                return ModuleSpellListEntrySnapshot(spellId: JSONHelpers.getLong(e["SpellId"]) ?? 0, index: JSONHelpers.getInt(e["Index"]) ?? 0, name: string(e["Name"]) ?? "")
            }
            d.config.itemsList = (config.array("ItemsList") ?? []).compactMap { node in
                guard let e = node.objectValue else { return nil }
                return ModuleItemListEntrySnapshot(itemId: JSONHelpers.getLong(e["ItemId"]) ?? 0, index: JSONHelpers.getInt(e["Index"]) ?? 0, name: string(e["Name"]) ?? "")
            }
        }
        if let macros = o.object("Macros") {
            d.macros.usesSpecDynamicSpells = JSONHelpers.getBool(macros["UsesSpecDynamicSpells"]) ?? false
            d.macros.dynamicCommon = (macros.array("DynamicCommon") ?? []).compactMap(string)
            d.macros.dynamicForSpec = (macros.array("DynamicForSpec") ?? []).compactMap(string)
            d.macros.staticSpells = decodeMacroEntries(macros.array("StaticSpells"))
            d.macros.specialSpells = decodeMacroEntries(macros.array("SpecialSpells"))
        }
        return d
    }

    static func decodeMacroEntries(_ array: [JSONValue]?) -> [ModuleMacroEntrySnapshot] {
        (array ?? []).compactMap { node in
            guard let e = node.objectValue else { return nil }
            return ModuleMacroEntrySnapshot(text: string(e["Text"]) ?? "", comment: string(e["Comment"]))
        }
    }

    static func decodeSpecSnapshot(_ o: JSONObject) -> ModuleSpecSnapshot {
        var s = ModuleSpecSnapshot()
        s.nestedStates = JSONHelpers.getBool(o["NestedStates"]) ?? true
        s.flatStates = (o.array("FlatStates") ?? []).compactMap(string)
        if let categorized = o.object("CategorizedStates") {
            for (key, node) in categorized.entries {
                s.categorizedStates[key] = (node.arrayValue ?? []).compactMap(string)
            }
        }
        s.items = (o.array("Items") ?? []).compactMap { node in
            guard let e = node.objectValue else { return nil }
            return ModuleItemSnapshot(itemId: JSONHelpers.getLong(e["ItemId"]) ?? 0, name: string(e["Name"]) ?? "", isEquipped: JSONHelpers.getBool(e["IsEquipped"]) ?? false)
        }
        s.playerAuras = decodeAuras(o.array("PlayerAuras"))
        s.targetHarmfulAuras = decodeAuras(o.array("TargetHarmfulAuras"))
        s.targetHelpfulAuras = decodeAuras(o.array("TargetHelpfulAuras"))
        s.focusHarmfulAuras = decodeAuras(o.array("FocusHarmfulAuras"))
        s.focusHelpfulAuras = decodeAuras(o.array("FocusHelpfulAuras"))
        s.spells = (o.array("Spells") ?? []).compactMap { node in
            guard let e = node.objectValue else { return nil }
            var sp = ModuleSpellSnapshot()
            sp.name = string(e["Name"]) ?? ""
            sp.spellId = JSONHelpers.getLong(e["SpellId"]) ?? 0
            sp.charge = JSONHelpers.getBool(e["Charge"]) ?? false
            sp.maxCharge = JSONHelpers.getInt(e["MaxCharge"])
            sp.castCount = JSONHelpers.getInt(e["CastCount"])
            sp.forcedKnown = JSONHelpers.getBool(e["ForcedKnown"]) ?? false
            sp.inSpellBook = JSONHelpers.getBool(e["InSpellBook"]) ?? false
            return sp
        }
        if let g = o.object("Group") {
            var group = ModuleGroupSnapshot()
            group.num = JSONHelpers.getInt(g["Num"]) ?? 5
            group.healthPercent = JSONHelpers.getInt(g["HealthPercent"])
            group.role = JSONHelpers.getInt(g["Role"])
            group.dispel = JSONHelpers.getInt(g["Dispel"])
            group.auras = (g.array("Auras") ?? []).compactMap { node in
                guard let e = node.objectValue else { return nil }
                var a = ModuleGroupAuraSnapshot()
                a.offset = JSONHelpers.getInt(e["Offset"]) ?? 0
                a.name = string(e["Name"]) ?? ""
                a.spellId = JSONHelpers.getLong(e["SpellId"])
                a.spellIds = (e.array("SpellIds") ?? []).compactMap(JSONHelpers.getLong)
                return a
            }
            s.group = group
        }
        return s
    }

    static func decodeAuras(_ array: [JSONValue]?) -> [ModuleAuraSnapshot] {
        (array ?? []).compactMap { node in
            guard let e = node.objectValue else { return nil }
            return ModuleAuraSnapshot(name: string(e["Name"]) ?? "", spellId: JSONHelpers.getLong(e["SpellId"]),
                                      spellIds: (e.array("SpellIds") ?? []).compactMap(JSONHelpers.getLong), maxApps: JSONHelpers.getInt(e["MaxApps"]))
        }
    }

    /// C# StringOrNumberJsonConverter：数字/布尔也可作为字符串读取。
    static func string(_ node: JSONValue?) -> String? {
        guard let node else { return nil }
        switch node {
        case .null: return nil
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return JSONWriter.formatDouble(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    // MARK: Encode

    public static func encodeText(_ m: ModuleDefinition) -> String {
        JSONWriter.indented(.object(encode(m)))
    }

    public static func encode(_ m: ModuleDefinition) -> JSONObject {
        var o = JSONObject()
        o["Id"] = .string(m.id)
        o["Name"] = .string(m.name)
        o["Author"] = .string(m.author)
        o["RecommendedTalent"] = .string(m.recommendedTalent)
        o["Version"] = .string(m.version)
        if let v = m.unitMappingVersion { o["UnitMappingVersion"] = .int(Int64(v)) }
        o["Enabled"] = .bool(m.enabled)
        o["Match"] = .object(encodeMatch(m.match))
        o["Units"] = .array(m.units.map { .object(encodeUnit($0)) })
        o["Counts"] = .array(m.counts.map { .object(encodeCount($0)) })
        o["ValueAdjustments"] = .array(m.valueAdjustments.map { .object(encodeAdjustment($0)) })
        o["Rules"] = .array(m.rules.map { .object(encodeRule($0)) })
        if let deps = m.dependencies { o["Dependencies"] = .object(encodeDependencies(deps)) }
        return o
    }

    static func encodeMatch(_ m: ModuleMatch) -> JSONObject {
        var o = JSONObject()
        if let v = m.classId { o["ClassId"] = .int(Int64(v)) }
        if let v = m.specId { o["SpecId"] = .int(Int64(v)) }
        if let v = m.partyType { o["PartyType"] = .string(v) }
        if let v = m.heroTalent { o["HeroTalent"] = .int(Int64(v)) }
        return o
    }

    static func encodeRule(_ r: ModuleRule) -> JSONObject {
        var o = JSONObject()
        o["Enabled"] = .bool(r.enabled)
        o["Condition"] = .string(r.condition)
        o["Comment"] = .string(r.comment)
        if let v = r.delayMs { o["DelayMs"] = .int(Int64(v)) }
        if let v = r.logicDelayMs { o["LogicDelayMs"] = .int(Int64(v)) }
        if let v = r.continueLogic { o["ContinueLogic"] = .bool(v) }
        if let v = r.unit { o["Unit"] = .int(Int64(v)) }
        if let v = r.unitName { o["UnitName"] = .string(v) }
        o["Spell"] = .string(r.spell)
        if let v = r.macroCondition { o["MacroCondition"] = .string(v) }
        o["Hotkey"] = .string(r.hotkey)
        o["Step"] = .string(r.step)
        if let subs = r.subConditions { o["SubConditions"] = .array(subs.map { .string($0) }) }
        return o
    }

    static func encodeUnit(_ u: ModuleUnit) -> JSONObject {
        var o = JSONObject()
        o["Name"] = .string(u.name)
        if let v = u.healthName { o["HealthName"] = .string(v) }
        o["Kind"] = .string(u.kind.rawValue)
        if let v = u.healthThreshold { o["HealthThreshold"] = .int(Int64(v)) }
        if let v = u.healthThresholdField { o["HealthThresholdField"] = .string(v) }
        if let v = u.roleFilter { o["RoleFilter"] = .string(v.rawValue) }
        if let v = u.role { o["Role"] = .int(Int64(v)) }
        o["Reverse"] = .bool(u.reverse)
        if let v = u.auraSpellIds { o["AuraSpellIds"] = .array(v.map { .int($0) }) }
        if let v = u.auraNames { o["AuraNames"] = .array(v.map { .string($0) }) }
        if let v = u.auraCount { o["AuraCount"] = .int(Int64(v)) }
        if let v = u.dispelType { o["DispelType"] = .int(Int64(v)) }
        return o
    }

    static func encodeCount(_ c: ModuleCountField) -> JSONObject {
        var o = JSONObject()
        o["Name"] = .string(c.name)
        o["Kind"] = .string(c.kind.rawValue)
        if let v = c.healthThreshold { o["HealthThreshold"] = .int(Int64(v)) }
        if let v = c.healthThresholdField { o["HealthThresholdField"] = .string(v) }
        if let v = c.auraSpellId { o["AuraSpellId"] = .int(v) }
        if let v = c.auraName { o["AuraName"] = .string(v) }
        if let v = c.roleFilter { o["RoleFilter"] = .string(v.rawValue) }
        if let v = c.role { o["Role"] = .int(Int64(v)) }
        return o
    }

    static func encodeAdjustment(_ a: ModuleValueAdjustment) -> JSONObject {
        var o = JSONObject()
        o["Enabled"] = .bool(a.enabled)
        o["Condition"] = .string(a.condition)
        o["Field"] = .string(a.field)
        o["Delta"] = .int(Int64(a.delta))
        o["Formula"] = .string(a.formula)
        return o
    }

    static func encodeDependencies(_ d: ModuleDependencySnapshot) -> JSONObject {
        var o = JSONObject()
        o["SchemaVersion"] = .int(Int64(d.schemaVersion))
        o["ClassId"] = .int(Int64(d.classId))
        o["SpecId"] = .int(Int64(d.specId))
        var config = JSONObject()
        config["Spec"] = .object(encodeSpecSnapshot(d.config.spec))
        config["SpellsList"] = .array(d.config.spellsList.map { e in
            .object(JSONObject([("SpellId", .int(e.spellId)), ("Index", .int(Int64(e.index))), ("Name", .string(e.name))]))
        })
        config["ItemsList"] = .array(d.config.itemsList.map { e in
            .object(JSONObject([("ItemId", .int(e.itemId)), ("Index", .int(Int64(e.index))), ("Name", .string(e.name))]))
        })
        o["Config"] = .object(config)
        var macros = JSONObject()
        macros["UsesSpecDynamicSpells"] = .bool(d.macros.usesSpecDynamicSpells)
        macros["DynamicCommon"] = .array(d.macros.dynamicCommon.map { .string($0) })
        macros["DynamicForSpec"] = .array(d.macros.dynamicForSpec.map { .string($0) })
        macros["StaticSpells"] = .array(d.macros.staticSpells.map { .object(encodeMacroEntry($0)) })
        macros["SpecialSpells"] = .array(d.macros.specialSpells.map { .object(encodeMacroEntry($0)) })
        o["Macros"] = .object(macros)
        return o
    }

    static func encodeMacroEntry(_ e: ModuleMacroEntrySnapshot) -> JSONObject {
        var o = JSONObject()
        o["Text"] = .string(e.text)
        if let c = e.comment { o["Comment"] = .string(c) }
        return o
    }

    static func encodeSpecSnapshot(_ s: ModuleSpecSnapshot) -> JSONObject {
        var o = JSONObject()
        o["NestedStates"] = .bool(s.nestedStates)
        o["FlatStates"] = .array(s.flatStates.map { .string($0) })
        var categorized = JSONObject()
        for key in s.categorizedStates.keys.sorted(by: { categoryOrder($0) < categoryOrder($1) }) {
            categorized[key] = .array(s.categorizedStates[key]!.map { .string($0) })
        }
        o["CategorizedStates"] = .object(categorized)
        o["Items"] = .array(s.items.map { .object(JSONObject([("ItemId", .int($0.itemId)), ("Name", .string($0.name)), ("IsEquipped", .bool($0.isEquipped))])) })
        o["PlayerAuras"] = .array(s.playerAuras.map { .object(encodeAura($0)) })
        o["TargetHarmfulAuras"] = .array(s.targetHarmfulAuras.map { .object(encodeAura($0)) })
        o["TargetHelpfulAuras"] = .array(s.targetHelpfulAuras.map { .object(encodeAura($0)) })
        o["FocusHarmfulAuras"] = .array(s.focusHarmfulAuras.map { .object(encodeAura($0)) })
        o["FocusHelpfulAuras"] = .array(s.focusHelpfulAuras.map { .object(encodeAura($0)) })
        o["Spells"] = .array(s.spells.map { sp in
            var e = JSONObject()
            e["Name"] = .string(sp.name)
            e["SpellId"] = .int(sp.spellId)
            e["Charge"] = .bool(sp.charge)
            if let v = sp.maxCharge { e["MaxCharge"] = .int(Int64(v)) }
            if let v = sp.castCount { e["CastCount"] = .int(Int64(v)) }
            e["ForcedKnown"] = .bool(sp.forcedKnown)
            e["InSpellBook"] = .bool(sp.inSpellBook)
            return .object(e)
        })
        if let g = s.group {
            var e = JSONObject()
            e["Num"] = .int(Int64(g.num))
            if let v = g.healthPercent { e["HealthPercent"] = .int(Int64(v)) }
            if let v = g.role { e["Role"] = .int(Int64(v)) }
            if let v = g.dispel { e["Dispel"] = .int(Int64(v)) }
            e["Auras"] = .array(g.auras.map { a in
                var ae = JSONObject()
                ae["Offset"] = .int(Int64(a.offset))
                ae["Name"] = .string(a.name)
                if let v = a.spellId { ae["SpellId"] = .int(v) }
                ae["SpellIds"] = .array(a.spellIds.map { .int($0) })
                return .object(ae)
            })
            o["Group"] = .object(e)
        }
        return o
    }

    static func encodeAura(_ a: ModuleAuraSnapshot) -> JSONObject {
        var o = JSONObject()
        o["Name"] = .string(a.name)
        if let v = a.spellId { o["SpellId"] = .int(v) }
        o["SpellIds"] = .array(a.spellIds.map { .int($0) })
        if let v = a.maxApps { o["MaxApps"] = .int(Int64(v)) }
        return o
    }

    private static func categoryOrder(_ category: String) -> Int {
        ClassStateCatalog.topCategories.firstIndex(of: category) ?? Int.max
    }
}
