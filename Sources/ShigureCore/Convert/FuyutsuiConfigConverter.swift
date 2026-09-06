import Foundation

public struct ConvertError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// 将 Fuyutsui class/*.lua 的 ClassBlocks 编译为 config/*.json（对齐 LoadPlayerBlocks 占位顺序）。
/// 输出格式与 C# 版逐字节一致（UTF-8 BOM、2 空格缩进、键序）。
public enum FuyutsuiConfigConverter {
    public struct UpdateResult: Sendable {
        public let classDirectory: URL
        public let updatedFiles: [URL]
        public let warnings: [String]
    }

    static let commonStateNames: Set<String> = ["锚点", "职业", "专精"]
    static let boolFieldNames: Set<String> = ["锚点", "有效性", "移动"]
    static let stateCategoryOrder = ClassStateCatalog.topCategories

    public static func updateFromClassDirectory(_ classDirectory: URL, configDirectory: URL) throws -> UpdateResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: classDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw ConvertError("找不到 Fuyutsui class 目录: \(classDirectory.path)")
        }
        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try ensureCommonConfig(configDirectory)

        var updated: [URL] = []
        var warnings: [String] = []
        for cls in ClassNames.allClasses {
            let fileName = ClassNames.configFileName(cls.id)
            let luaURL = classDirectory.appendingPathComponent("\(fileName).lua")
            guard fm.fileExists(atPath: luaURL.path) else {
                warnings.append("跳过 \(fileName): 未找到 \(luaURL.path)")
                continue
            }
            let jsonURL = configDirectory.appendingPathComponent("\(fileName).json")
            let existing: JSONObject
            if fm.fileExists(atPath: jsonURL.path), let text = try? TextFile.read(jsonURL), let obj = try? JSONParser.parseObject(text) {
                existing = obj
            } else {
                existing = JSONObject()
            }
            let lua = try TextFile.read(luaURL)
            let (root, classWarnings) = try compileClass(lua: lua, fileName: fileName, existing: existing)
            warnings.append(contentsOf: classWarnings)
            try AtomicFile.write(JSONWriter.indented(.object(root)) + "\n", to: jsonURL, withBOM: true)
            updated.append(jsonURL)
        }
        if updated.isEmpty {
            throw ConvertError("未成功转换任何职业配置。")
        }
        return UpdateResult(classDirectory: classDirectory, updatedFiles: updated, warnings: warnings)
    }

    /// 单个职业：Lua 文本 → config JSON 对象（供测试与更新流程共用）。
    public static func compileClass(lua: String, fileName: String, existing: JSONObject) throws -> (JSONObject, [String]) {
        var warnings: [String] = []
        guard let classBlocks = LuaLiteParser.extractAssignedTable(lua, "Fuyutsui.ClassBlocks") else {
            throw ConvertError("\(fileName).lua 中未找到 Fuyutsui.ClassBlocks")
        }
        let spellsList = LuaLiteParser.extractAssignedTable(lua, "Fuyutsui.spellsList")
        let itemsList = LuaLiteParser.extractAssignedTable(lua, "Fuyutsui.itemsList")

        var root = JSONObject()
        for key in ["keymap", "一键法术", ModuleSpecialActions.oneKeyItem] {
            if let node = existing[key] { root[key] = node }
        }
        if root["keymap"] == nil {
            root["keymap"] = .string(fileName.lowercased() + ".json")
        }
        if let spellsList {
            root[ModuleSpecialActions.oneKeySpell] = .object(compileIdMap(spellsList, idKey: "spellId", mapName: "一键法术", listName: "spellsList", warnings: &warnings, label: fileName))
        } else {
            warnings.append("\(fileName): 未找到 Fuyutsui.spellsList，已保留现有一键法术")
        }
        if let itemsList {
            root[ModuleSpecialActions.oneKeyItem] = .object(compileIdMap(itemsList, idKey: "itemId", mapName: ModuleSpecialActions.oneKeyItem, listName: "itemsList", warnings: &warnings, label: fileName))
        } else {
            warnings.append("\(fileName): 未找到 Fuyutsui.itemsList，已保留现有一键物品")
        }

        for specId in 1...4 {
            guard let specTable = classBlocks.table(Int64(specId)) else { continue }
            let (specJson, specWarnings) = compileSpec(specTable, label: "\(fileName)[\(specId)]")
            warnings.append(contentsOf: specWarnings)
            if !specJson.isEmpty {
                root[String(specId)] = .object(specJson)
            }
        }
        return (root, warnings)
    }

    static func ensureCommonConfig(_ configDirectory: URL) throws {
        let commonURL = configDirectory.appendingPathComponent(ConfigService.commonConfigFileName)
        guard !FileManager.default.fileExists(atPath: commonURL.path) else { return }
        var root = JSONObject()
        root["锚点"] = .object(JSONObject([("step", .int(1)), ("type", .string("bool"))]))
        root["职业"] = .object(JSONObject([("step", .int(2)), ("type", .string("int"))]))
        root["专精"] = .object(JSONObject([("step", .int(3)), ("type", .string("int"))]))
        try AtomicFile.write(JSONWriter.indented(.object(root)) + "\n", to: commonURL, withBOM: true)
    }

    /// spellsList/itemsList → { index: id }，按 index 升序；index 冲突保留前者。
    private static func compileIdMap(_ list: LuaTable, idKey: String, mapName: String, listName: String, warnings: inout [String], label: String) -> JSONObject {
        var map: [Int: Int64] = [:]
        var order: [Int] = []
        for entry in list.entries {
            guard case .table(let item) = entry.value else { continue }
            let indexValue = item.number("index")
            let idValue: Double?
            switch entry.key {
            case .int(let n)?: idValue = Double(n)
            default: idValue = item.number(idKey)
            }
            guard let indexValue, indexValue > 0, indexValue <= Double(Int32.max), indexValue == indexValue.rounded(.towardZero),
                  let idValue, idValue > 0, idValue == idValue.rounded(.towardZero) else {
                warnings.append("\(label): \(listName) 条目缺少有效 index/\(idKey)，已跳过")
                continue
            }
            let index = Int(indexValue)
            let id = Int64(idValue)
            if let existing = map[index] {
                if existing != id {
                    warnings.append("\(label): \(mapName) index \(index) 同时对应 id \(existing) 和 \(id)，已保留前者")
                }
            } else {
                map[index] = id
                order.append(index)
            }
        }
        var result = JSONObject()
        for index in order.sorted() {
            result[String(index)] = .int(map[index]!)
        }
        return result
    }

    static func compileSpec(_ spec: LuaTable, label: String) -> (JSONObject, [String]) {
        var warnings: [String] = []
        var result = JSONObject()
        var index = 1

        if let states = spec.table("states") {
            let nested = stateCategoryOrder.contains { states.table($0) != nil }
            if nested {
                for category in stateCategoryOrder {
                    guard let list = states.table(category) else { continue }
                    for item in list.ipairs() {
                        guard case .string(let raw) = item, !raw.isBlank else { continue }
                        let stateName = normalizeStateName(raw)
                        let key = isUnitStateCategory(category) ? category + stateName : stateName
                        addStateField(&result, name: key, step: index, classification: category)
                        index += 1
                    }
                }
            } else {
                for item in states.ipairs() {
                    guard case .string(let raw) = item, !raw.isBlank else { continue }
                    let stateName = normalizeStateName(raw)
                    addStateField(&result, name: stateName, step: index,
                                  classification: ClassStateCatalog.findCategory(stateName) ?? ClassStateCatalog.categoryState)
                    index += 1
                }
            }
        }

        var aurasObject = JSONObject()
        var playerAuraBarNames: [String] = []
        if let auras = spec.table("auras") {
            let nested = auras.table("player") != nil || auras.table("target") != nil || auras.table("focus") != nil
            if nested {
                appendAuraList(auras.table("player"), classification: "玩家", includeApplicationBars: true, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
                if let target = auras.table("target") {
                    appendAuraList(target.table("harmful"), classification: "目标减益", includeApplicationBars: true, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
                    appendAuraList(target.table("helpful"), classification: "目标增益", includeApplicationBars: false, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
                }
                if let focus = auras.table("focus") {
                    appendAuraList(focus.table("harmful"), classification: "焦点减益", includeApplicationBars: true, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
                    appendAuraList(focus.table("helpful"), classification: "焦点增益", includeApplicationBars: false, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
                }
            } else {
                appendAuraList(auras, classification: "玩家", includeApplicationBars: true, into: &aurasObject, index: &index, barNames: &playerAuraBarNames, warnings: &warnings, label: label)
            }
        }

        var spellsObject = JSONObject()
        var barIndex = 1
        var barSpellIds = Set<Int64>()
        if let spells = spec.table("spells") {
            for item in spells.ipairs() {
                guard case .table(let spell) = item else { continue }
                guard let spellIdNumber = spell.number("spellId") else {
                    warnings.append("\(label): spell 缺少 spellId，已跳过")
                    continue
                }
                let id = Int64(spellIdNumber.rounded(.towardZero))
                var name = spell.string("name")?.trimmed() ?? ""
                if name.isBlank { name = String(id) }

                spellsObject["\(id).\(SpellFieldKey.spellCooldown)"] = .object(spellField(step: index, displayName: name, spellId: id, metric: SpellFieldKey.spellCooldown, displayType: "冷却"))
                index += 1

                let charge = spell.bool("charge") == true
                if charge {
                    spellsObject["\(id).\(SpellFieldKey.spellChargeCooldown)"] = .object(spellField(step: index, displayName: ensureSuffix(name, "充能"), spellId: id, metric: SpellFieldKey.spellChargeCooldown, displayType: "充能"))
                    index += 1
                }
                if charge, spell.number("maxCharge") != nil, barSpellIds.insert(id).inserted {
                    spellsObject["\(id).\(SpellFieldKey.spellCount)"] = .object(spellBarField(bar: barIndex, displayName: ensureSuffix(name, "层数"), spellId: id, metric: SpellFieldKey.spellCount, displayType: "充能层数"))
                    barIndex += 1
                }
                if let castCount = spell.number("castCount"), castCount > 0, barSpellIds.insert(id).inserted {
                    spellsObject["\(id).\(SpellFieldKey.spellCount)"] = .object(spellBarField(bar: barIndex, displayName: ensureSuffix(name, "层数"), spellId: id, metric: SpellFieldKey.spellCount, displayType: "施法次数"))
                    barIndex += 1
                }
            }
        }

        for barName in playerAuraBarNames {
            if var metadata = aurasObject.object(barName) {
                metadata["step"] = .string("bar")
                metadata["bar"] = .int(Int64(barIndex))
                barIndex += 1
                aurasObject[barName] = .object(metadata)
            }
        }

        if let items = spec.table("items") {
            for item in readItems(items, warnings: &warnings, label: label) {
                if result.contains(item.name) {
                    warnings.append("\(label): 物品名称“\(item.name)”与已有状态字段重复，已跳过该物品字段")
                } else {
                    var field = makeField(step: index, type: "int", classification: ClassStateCatalog.categoryItem)
                    field["itemId"] = .int(item.itemId)
                    field["isEquipped"] = .bool(item.isEquipped)
                    result[item.name] = .object(field)
                    index += 1
                }
            }
        }

        if !aurasObject.isEmpty { result["auras"] = .object(aurasObject) }
        if !spellsObject.isEmpty { result["spells"] = .object(spellsObject) }

        if let group = spec.table("group") {
            var groupJson = JSONObject()
            groupJson["start"] = .int(Int64(index))
            groupJson["num"] = .int(Int64((group.number("num") ?? 5).rounded(.towardZero)))
            addGroupOffset(&groupJson, group.number("healthPercent"), "生命值")
            addGroupOffset(&groupJson, group.number("role"), "职责")
            addGroupOffset(&groupJson, group.number("dispel"), "驱散")
            if let auraOffsets = group.table("aura") {
                for entry in auraOffsets.entries {
                    guard case .int(let offset)? = entry.key, case .table(let auraInfo) = entry.value else { continue }
                    var auraName = auraInfo.string("name")?.trimmed() ?? ""
                    if auraName.isBlank { auraName = "光环\(offset)" }
                    let ids = readAuraIds(auraInfo)
                    guard let canonical = SpellFieldKey.canonicalAuraId(spellId: auraInfo.number("spellId").map { Int64($0.rounded(.towardZero)) }, spellIds: ids) else {
                        warnings.append("\(label): group aura“\(auraName)”缺少有效 spellId，已跳过")
                        continue
                    }
                    groupJson["auras.\(canonical).\(SpellFieldKey.auraValue)"] = .object(auraField(step: Int(offset), displayName: auraName, spellId: canonical, scope: "group", metric: SpellFieldKey.auraValue, aliases: ids, classification: nil))
                }
            }
            result["group"] = .object(groupJson)
        }

        return (result, warnings)
    }

    struct ItemInfo { let itemId: Int64; let name: String; let isEquipped: Bool }

    static func readItems(_ list: LuaTable, warnings: inout [String], label: String) -> [ItemInfo] {
        var result: [ItemInfo] = []
        var seen = Set<Int64>()
        for entry in list.entries {
            guard case .int(let itemId)? = entry.key, itemId > 0, case .table(let itemTable) = entry.value, seen.insert(itemId).inserted else { continue }
            let name = itemTable.string("name")?.trimmed() ?? ""
            if name.isBlank {
                seen.remove(itemId)
                warnings.append("\(label): itemId \(itemId) 缺少名称，已跳过")
                continue
            }
            result.append(ItemInfo(itemId: itemId, name: name, isEquipped: itemTable.bool("isEquipped") == true))
        }
        return result.sorted { $0.itemId < $1.itemId }
    }

    private static func appendAuraList(_ list: LuaTable?, classification: String, includeApplicationBars: Bool, into aurasObject: inout JSONObject, index: inout Int, barNames: inout [String], warnings: inout [String], label: String) {
        guard let list else { return }
        for item in list.ipairs() {
            guard case .table(let aura) = item else { continue }
            if aura.number("spellId") == nil && aura.get("spellIds") == nil {
                warnings.append("\(label): aura 缺少 spellId/spellIds，已跳过")
                continue
            }
            var name = aura.string("name")?.trimmed() ?? ""
            if name.isBlank { name = "未命名光环" }
            let ids = readAuraIds(aura)
            guard let canonical = SpellFieldKey.canonicalAuraId(spellId: aura.number("spellId").map { Int64($0.rounded(.towardZero)) }, spellIds: ids) else {
                warnings.append("\(label): aura“\(name)”缺少有效 spellId，已跳过")
                continue
            }
            let scope: String
            switch classification {
            case "目标减益": scope = "target.harmful"
            case "目标增益": scope = "target.helpful"
            case "焦点减益": scope = "focus.harmful"
            case "焦点增益": scope = "focus.helpful"
            default: scope = "player"
            }
            aurasObject["\(scope).\(canonical).\(SpellFieldKey.auraValue)"] = .object(auraField(step: index, displayName: name, spellId: canonical, scope: scope, metric: SpellFieldKey.auraValue, aliases: ids, classification: classification))
            index += 1
            if aura.number("maxApps") != nil, includeApplicationBars {
                let appsKey = "\(scope).\(canonical).\(SpellFieldKey.auraApplications)"
                aurasObject[appsKey] = .object(auraField(step: 0, displayName: ensureSuffix(name, "层数"), spellId: canonical, scope: scope, metric: SpellFieldKey.auraApplications, aliases: ids, classification: classification))
                barNames.append(appsKey)
            }
        }
    }

    static func readAuraIds(_ aura: LuaTable) -> [Int64] {
        var result: [Int64] = []
        if let spellId = aura.number("spellId"), spellId > 0 {
            result.append(Int64(spellId.rounded(.towardZero)))
        }
        if let spellIds = aura.table("spellIds") {
            for item in spellIds.ipairs() {
                guard let id = item.intValue, id > 0, !result.contains(id) else { continue }
                result.append(id)
            }
        }
        return result
    }

    private static func addStateField(_ result: inout JSONObject, name: String, step: Int, classification: String) {
        if commonStateNames.contains(name) { return }
        result[name] = .object(makeField(step: step, type: boolFieldNames.contains(name) ? "bool" : "int", classification: classification))
    }

    private static func addGroupOffset(_ groupJson: inout JSONObject, _ offset: Double?, _ name: String) {
        guard let offset else { return }
        groupJson[name] = .object(makeField(step: Int(offset.rounded(.towardZero)), type: "int", classification: nil))
    }

    static func makeField(step: Int, type: String, classification: String?) -> JSONObject {
        var field = JSONObject()
        field["step"] = .int(Int64(step))
        field["type"] = .string(type)
        if let classification, !classification.isBlank {
            field["category"] = .string(classification)
        }
        return field
    }

    private static func spellField(step: Int, displayName: String, spellId: Int64, metric: String, displayType: String) -> JSONObject {
        var field = makeField(step: step, type: "int", classification: nil)
        addSpellMetadata(&field, displayName: displayName, spellId: spellId, metric: metric, displayType: displayType)
        return field
    }

    private static func spellBarField(bar: Int, displayName: String, spellId: Int64, metric: String, displayType: String) -> JSONObject {
        var field = JSONObject()
        field["step"] = .string("bar")
        field["bar"] = .int(Int64(bar))
        field["type"] = .string("int")
        addSpellMetadata(&field, displayName: displayName, spellId: spellId, metric: metric, displayType: displayType)
        return field
    }

    private static func addSpellMetadata(_ field: inout JSONObject, displayName: String, spellId: Int64, metric: String, displayType: String) {
        field["displayName"] = .string(displayName)
        field["spellId"] = .int(spellId)
        field["metric"] = .string(metric)
        field["displayType"] = .string(displayType)
    }

    private static func auraField(step: Int, displayName: String, spellId: Int64, scope: String, metric: String, aliases: [Int64], classification: String?) -> JSONObject {
        var field = makeField(step: step, type: "int", classification: classification)
        field["displayName"] = .string(displayName)
        field["spellId"] = .int(spellId)
        field["scope"] = .string(scope)
        field["metric"] = .string(metric)
        var seen = Set<Int64>()
        field["spellIds"] = .array(aliases.filter { $0 > 0 && seen.insert($0).inserted }.map { .int($0) })
        return field
    }

    static func ensureSuffix(_ name: String, _ suffix: String) -> String {
        name.hasSuffix(suffix) ? name : name + suffix
    }

    static func normalizeStateName(_ name: String) -> String {
        name == "法术失败" ? ModuleSpecialActions.insertSpellState : name
    }

    static func isUnitStateCategory(_ category: String) -> Bool {
        ClassStateCatalog.isUnitPrefixCategory(category)
    }
}
