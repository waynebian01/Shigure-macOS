import Foundation

/// rowData/barData/healAbsorbData → GameState（对应 C# StateBuilder）。
public struct StateBuilder: Sendable {
    private let config: ConfigService

    public init(config: ConfigService) {
        self.config = config
    }

    public func build(rowData: [Int: Int], barData: [Int: Int], healAbsorbData: [Int: Int]) -> GameState {
        let classId = rowData[2] ?? 0
        let specId = rowData[3] ?? 0
        let stateConfig = config.buildStateConfig(classId: classId, specId: specId)
        var state = GameState()

        for (key, node) in stateConfig.entries {
            if key == "group" || key == "spells" || key == "auras" { continue }
            guard case .object(let field) = node, field.contains("step") else { continue }
            state.setValue(key, Self.convert(Self.resolveRaw(field, rowData, barData), type: JSONHelpers.getString(field["type"])))
            if let itemId = JSONHelpers.getLong(field["itemId"]), itemId > 0 {
                state.itemIds[key] = itemId
            }
        }

        if let spellsConfig = stateConfig.object("spells") {
            for (fieldName, node) in spellsConfig.entries {
                guard case .object(let field) = node, field.contains("step") else { continue }
                let value = Self.convert(Self.resolveRaw(field, rowData, barData), type: JSONHelpers.getString(field["type"]))
                state.setSpell(fieldName, value)
                for (aliasKey, aliasValue) in Self.auraAliases(field, value, includeScope: true) {
                    state.setSpell(aliasKey, aliasValue)
                }
                if let displayType = JSONHelpers.getString(field["displayType"]), !displayType.isBlank {
                    state.spellDisplayTypes[fieldName] = displayType
                }
            }
        }

        if let aurasConfig = stateConfig.object("auras") {
            for (fieldName, node) in aurasConfig.entries {
                guard case .object(let field) = node, field.contains("step") else { continue }
                let value = Self.convert(Self.resolveRaw(field, rowData, barData), type: JSONHelpers.getString(field["type"]))
                state.setAura(fieldName, value)
                for (aliasKey, aliasValue) in Self.auraAliases(field, value, includeScope: true) {
                    state.setAura(aliasKey, aliasValue)
                }
            }
        }

        if let groupConfig = stateConfig.object("group") {
            state.group = Self.buildGroup(groupConfig, rowData, barData, healAbsorbData)
        }

        return state
    }

    private static func buildGroup(_ groupConfig: JSONObject, _ rowData: [Int: Int], _ barData: [Int: Int], _ healAbsorbData: [Int: Int]) -> [String: [String: StateValue?]] {
        let start = JSONHelpers.getInt(groupConfig["start"]) ?? 26
        let num = JSONHelpers.getInt(groupConfig["num"]) ?? 5
        var group: [String: [String: StateValue?]] = [:]
        for i in 1...30 {
            let baseStep = start + (i - 1) * num
            var sub: [String: StateValue?] = [:]
            for (fieldName, node) in groupConfig.entries {
                if fieldName == "start" || fieldName == "num" { continue }
                guard case .object(let field) = node, field.contains("step") else { continue }
                let raw: Int?
                if JSONHelpers.getString(field["step"]) == "bar" {
                    raw = resolveRaw(field, rowData, barData)
                } else if let rel = JSONHelpers.getInt(field["step"]) {
                    raw = rowData[baseStep + rel]
                } else {
                    raw = nil
                }
                let value = convert(raw, type: JSONHelpers.getString(field["type"]))
                sub[fieldName] = .some(value)
                for (aliasKey, aliasValue) in auraAliases(field, value, includeScope: false) {
                    sub[aliasKey] = .some(aliasValue)
                }
            }
            // 治疗吸收来自网格扫描；插件像素里的生命值含吸收盾，折算为真实生命：生命值 -= 治疗吸收（保留 0 和负数）。
            let absorb = healAbsorbData[i] ?? 0
            sub["治疗吸收"] = .some(.int(absorb))
            if absorb != 0, case .int(let health)? = sub["生命值"] ?? nil {
                sub["生命值"] = .some(.int(health - absorb))
            }
            group[String(i)] = sub
        }
        return group
    }

    private static func auraAliases(_ field: JSONObject, _ value: StateValue, includeScope: Bool) -> [(String, StateValue)] {
        guard let canonical = JSONHelpers.getLong(field["spellId"]),
              let metric = JSONHelpers.getString(field["metric"]), !metric.isBlank,
              let aliases = field.array("spellIds") else { return [] }
        let scope = JSONHelpers.getString(field["scope"]) ?? ""
        var result: [(String, StateValue)] = []
        for node in aliases {
            guard let alias = JSONHelpers.getLong(node), alias != canonical else { continue }
            let key = includeScope ? "\(scope).\(alias).\(metric)" : "auras.\(alias).\(metric)"
            result.append((key, value))
        }
        return result
    }

    static func resolveRaw(_ field: JSONObject, _ rowData: [Int: Int], _ barData: [Int: Int]) -> Int? {
        if JSONHelpers.getString(field["step"]) == "bar" {
            guard let barIndex = JSONHelpers.getInt(field["bar"]) else { return nil }
            return barData[barIndex]
        }
        guard let step = JSONHelpers.getInt(field["step"]) else { return nil }
        return rowData[step]
    }

    static func convert(_ raw: Int?, type: String?) -> StateValue {
        switch type {
        case "bool": return .bool((raw ?? 0) != 0)
        case "string": return .string(raw.map(String.init) ?? "")
        default: return .int(raw ?? 0)
        }
    }
}
