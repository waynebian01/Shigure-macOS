import Foundation

public struct ConfigError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
    public init(_ message: String) { self.message = message }
}

/// config/common.json + 13 个职业 config JSON 的只读视图（对应 C# ConfigService）。
public struct ConfigService: Sendable {
    public static let configDirectoryName = "config"
    public static let commonConfigFileName = "common.json"
    static let fixedStateNames = ["锚点", "职业", "专精"]

    public let root: JSONObject

    public init(root: JSONObject) {
        self.root = root
    }

    /// 读取 `configDirectory/common.json` 与每个职业文件；任一缺失即失败（无部分配置模式）。
    public static func load(configDirectory: URL) throws -> ConfigService {
        let commonURL = configDirectory.appendingPathComponent(commonConfigFileName)
        guard FileManager.default.fileExists(atPath: commonURL.path) else {
            throw ConfigError("找不到公共 config 配置: \(commonURL.path)")
        }
        var root = try readObject(commonURL)
        for cls in ClassNames.allClasses {
            var classURL = configDirectory.appendingPathComponent("\(ClassNames.configFileName(cls.id)).json")
            if !FileManager.default.fileExists(atPath: classURL.path) {
                classURL = configDirectory.appendingPathComponent("\(cls.id).json")
            }
            guard FileManager.default.fileExists(atPath: classURL.path) else {
                throw ConfigError("找不到职业 config 配置: \(classURL.path)")
            }
            root[String(cls.id)] = .object(try readObject(classURL))
        }
        return ConfigService(root: root)
    }

    static func readObject(_ url: URL) throws -> JSONObject {
        let text = try TextFile.read(url)
        do {
            return try JSONParser.parseObject(text)
        } catch {
            throw ConfigError("\(url.lastPathComponent) 不是有效的 JSON 对象: \(error)")
        }
    }

    public func object(_ path: String...) -> JSONObject? {
        var node: JSONValue = .object(root)
        for part in path {
            guard case .object(let obj) = node, let next = obj[part] else { return nil }
            node = next
        }
        return node.objectValue
    }

    /// 合并公共字段、可选 `state` 对象与指定职业/专精对象；固定字段始终以 common 为准。
    public func buildStateConfig(classId: Int?, specId: Int?) -> JSONObject {
        var merged = JSONObject()
        for (key, node) in root.entries {
            if case .object(let obj) = node, obj.contains("step") {
                merged[key] = node
            }
        }
        if let state = root.object("state") {
            for (key, value) in state.entries { merged[key] = value }
        }
        if let classId, let specId, let spec = object(String(classId), String(specId)) {
            for (key, value) in spec.entries { merged[key] = value }
        }
        for name in Self.fixedStateNames {
            if let fixed = root[name] { merged[name] = fixed }
        }
        return merged
    }

    public func keymapName(classId: Int?) -> String {
        guard let classId, let classObj = object(String(classId)), let node = classObj["keymap"] else {
            return "keymap.json"
        }
        let value = JSONHelpers.getString(node)
        return value.isNilOrBlank ? "keymap.json" : value!
    }

    public func failedSpells(classId: Int?) -> [Int: Int64] { classSpellMap(classId, ModuleSpecialActions.oneKeySpell) }
    public func oneKeySpells(classId: Int?) -> [Int: Int64] { classSpellMap(classId, ModuleSpecialActions.oneKeySpell) }
    public func insertItems(classId: Int?) -> [Int: Int64] { classSpellMap(classId, ModuleSpecialActions.oneKeyItem) }

    private func classSpellMap(_ classId: Int?, _ configKey: String) -> [Int: Int64] {
        guard let classId, let classObj = object(String(classId)), let map = classObj.object(configKey) else {
            return [:]
        }
        var result: [Int: Int64] = [:]
        for (idText, node) in map.entries {
            if let id = Int(idText), let spellId = JSONHelpers.getLong(node), spellId > 0 {
                result[id] = spellId
            }
        }
        return result
    }
}
