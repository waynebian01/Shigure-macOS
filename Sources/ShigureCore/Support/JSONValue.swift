import Foundation

/// 保持键插入顺序的 JSON 对象。config/keymap/模块文件都依赖键序（与 .NET JsonObject 行为一致）。
public struct JSONObject: Sendable, Equatable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public init(_ entries: [(String, JSONValue)]) {
        for (key, value) in entries {
            self[key] = value
        }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil {
                    keys.append(key)
                }
                storage[key] = newValue
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public func contains(_ key: String) -> Bool {
        storage[key] != nil
    }

    public var entries: [(key: String, value: JSONValue)] {
        keys.map { ($0, storage[$0]!) }
    }

    @discardableResult
    public mutating func remove(_ key: String) -> JSONValue? {
        guard let value = storage.removeValue(forKey: key) else { return nil }
        keys.removeAll { $0 == key }
        return value
    }

    public func object(_ key: String) -> JSONObject? {
        if case .object(let obj)? = storage[key] { return obj }
        return nil
    }

    public func array(_ key: String) -> [JSONValue]? {
        if case .array(let arr)? = storage[key] { return arr }
        return nil
    }
}

public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public var objectValue: JSONObject? {
        if case .object(let obj) = self { return obj }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let arr) = self { return arr }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

public struct JSONParseError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let offset: Int
    public var description: String { "\(message)（偏移 \(offset)）" }
}

// MARK: - Parser（支持 BOM、// 与 /* */ 注释、尾随逗号，与 .NET JsonDocumentOptions 相同的宽松模式）

public enum JSONParser {
    public static func parse(_ text: String) throws -> JSONValue {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" {
            scalars.removeFirst()
        }
        var parser = Impl(scalars: scalars)
        parser.skipTrivia()
        let value = try parser.parseValue()
        parser.skipTrivia()
        if parser.pos < parser.scalars.count {
            throw JSONParseError(message: "JSON 末尾存在多余内容", offset: parser.pos)
        }
        return value
    }

    public static func parse(data: Data) throws -> JSONValue {
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONParseError(message: "文件不是有效的 UTF-8", offset: 0)
        }
        return try parse(text)
    }

    public static func parseObject(_ text: String) throws -> JSONObject {
        guard case .object(let obj) = try parse(text) else {
            throw JSONParseError(message: "不是 JSON 对象", offset: 0)
        }
        return obj
    }

    private struct Impl {
        let scalars: [Unicode.Scalar]
        var pos = 0

        init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

        var current: Unicode.Scalar? { pos < scalars.count ? scalars[pos] : nil }

        mutating func skipTrivia() {
            while let c = current {
                if c == " " || c == "\t" || c == "\n" || c == "\r" {
                    pos += 1
                } else if c == "/" && pos + 1 < scalars.count && scalars[pos + 1] == "/" {
                    while let d = current, d != "\n" { pos += 1 }
                } else if c == "/" && pos + 1 < scalars.count && scalars[pos + 1] == "*" {
                    pos += 2
                    while pos + 1 < scalars.count && !(scalars[pos] == "*" && scalars[pos + 1] == "/") { pos += 1 }
                    pos = min(pos + 2, scalars.count)
                } else {
                    break
                }
            }
        }

        mutating func parseValue() throws -> JSONValue {
            guard let c = current else { throw JSONParseError(message: "意外结束", offset: pos) }
            switch c {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t": try expectWord("true"); return .bool(true)
            case "f": try expectWord("false"); return .bool(false)
            case "n": try expectWord("null"); return .null
            default:
                if c == "-" || (c.value >= 48 && c.value <= 57) { return try parseNumber() }
                throw JSONParseError(message: "无法识别的字符 '\(Character(c))'", offset: pos)
            }
        }

        mutating func expectWord(_ word: String) throws {
            for w in word.unicodeScalars {
                guard current == w else { throw JSONParseError(message: "期望 \(word)", offset: pos) }
                pos += 1
            }
        }

        mutating func parseObject() throws -> JSONValue {
            pos += 1
            var object = JSONObject()
            skipTrivia()
            if current == "}" { pos += 1; return .object(object) }
            while true {
                skipTrivia()
                if current == "}" { pos += 1; return .object(object) } // trailing comma
                guard current == "\"" else { throw JSONParseError(message: "期望属性名", offset: pos) }
                let key = try parseString()
                skipTrivia()
                guard current == ":" else { throw JSONParseError(message: "期望 ':'", offset: pos) }
                pos += 1
                skipTrivia()
                let value = try parseValue()
                object[key] = value
                skipTrivia()
                if current == "," { pos += 1; continue }
                if current == "}" { pos += 1; return .object(object) }
                throw JSONParseError(message: "期望 ',' 或 '}'", offset: pos)
            }
        }

        mutating func parseArray() throws -> JSONValue {
            pos += 1
            var items: [JSONValue] = []
            skipTrivia()
            if current == "]" { pos += 1; return .array(items) }
            while true {
                skipTrivia()
                if current == "]" { pos += 1; return .array(items) }
                items.append(try parseValue())
                skipTrivia()
                if current == "," { pos += 1; continue }
                if current == "]" { pos += 1; return .array(items) }
                throw JSONParseError(message: "期望 ',' 或 ']'", offset: pos)
            }
        }

        mutating func parseString() throws -> String {
            pos += 1
            var result = String.UnicodeScalarView()
            while let c = current {
                pos += 1
                if c == "\"" { return String(result) }
                if c == "\\" {
                    guard let e = current else { break }
                    pos += 1
                    switch e {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u":
                        var code = try parseHex4()
                        if code >= 0xD800 && code <= 0xDBFF, current == "\\", pos + 1 < scalars.count, scalars[pos + 1] == "u" {
                            pos += 2
                            let low = try parseHex4()
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        if let scalar = Unicode.Scalar(code) { result.append(scalar) }
                    default: throw JSONParseError(message: "无效转义 \\\(Character(e))", offset: pos)
                    }
                    continue
                }
                result.append(c)
            }
            throw JSONParseError(message: "字符串未闭合", offset: pos)
        }

        mutating func parseHex4() throws -> UInt32 {
            guard pos + 4 <= scalars.count else { throw JSONParseError(message: "无效 \\u 转义", offset: pos) }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let c = scalars[pos]
                pos += 1
                guard let digit = Character(c).hexDigitValue else { throw JSONParseError(message: "无效 \\u 转义", offset: pos) }
                value = value * 16 + UInt32(digit)
            }
            return value
        }

        mutating func parseNumber() throws -> JSONValue {
            let start = pos
            var isDouble = false
            if current == "-" { pos += 1 }
            while let c = current {
                if c.value >= 48 && c.value <= 57 { pos += 1; continue }
                if c == "." || c == "e" || c == "E" || c == "+" || c == "-" { isDouble = true; pos += 1; continue }
                break
            }
            let text = String(String.UnicodeScalarView(scalars[start..<pos]))
            if !isDouble, let i = Int64(text) { return .int(i) }
            guard let d = Double(text) else { throw JSONParseError(message: "无效数字 \(text)", offset: start) }
            return .double(d)
        }
    }
}

// MARK: - Writer（复刻 System.Text.Json WriteIndented + UnsafeRelaxedJsonEscaping 的输出格式）

public enum JSONWriter {
    /// 缩进 2 空格、`"key": value`、空对象 `{}`、空数组 `[]`、非 ASCII 原样输出。
    public static func indented(_ value: JSONValue) -> String {
        var out = ""
        write(value, indent: 0, into: &out)
        return out
    }

    public static func compact(_ value: JSONValue) -> String {
        var out = ""
        writeCompact(value, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, indent: Int, into out: inout String) {
        switch value {
        case .object(let obj):
            if obj.isEmpty { out += "{}"; return }
            out += "{\n"
            let pad = String(repeating: " ", count: (indent + 1) * 2)
            for (i, (key, item)) in obj.entries.enumerated() {
                out += pad
                out += quote(key)
                out += ": "
                write(item, indent: indent + 1, into: &out)
                out += i == obj.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: " ", count: indent * 2) + "}"
        case .array(let arr):
            if arr.isEmpty { out += "[]"; return }
            out += "[\n"
            let pad = String(repeating: " ", count: (indent + 1) * 2)
            for (i, item) in arr.enumerated() {
                out += pad
                write(item, indent: indent + 1, into: &out)
                out += i == arr.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: " ", count: indent * 2) + "]"
        default:
            writeCompact(value, into: &out)
        }
    }

    private static func writeCompact(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += formatDouble(d)
        case .string(let s): out += quote(s)
        case .array(let arr):
            out += "["
            for (i, item) in arr.enumerated() {
                if i > 0 { out += "," }
                writeCompact(item, into: &out)
            }
            out += "]"
        case .object(let obj):
            out += "{"
            for (i, (key, item)) in obj.entries.enumerated() {
                if i > 0 { out += "," }
                out += quote(key) + ":"
                writeCompact(item, into: &out)
            }
            out += "}"
        }
    }

    static func formatDouble(_ d: Double) -> String {
        if d.isNaN || d.isInfinite { return "null" }
        if d == d.rounded(.towardZero), abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    public static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}

// MARK: - JsonHelpers 语义（与 C# JsonHelpers 一致）

public enum JSONHelpers {
    /// int/long → Int（long 截断）；数字字符串可解析；其它 nil。
    public static func getInt(_ node: JSONValue?) -> Int? {
        guard let node else { return nil }
        switch node {
        case .int(let i): return Int(truncatingIfNeeded: Int32(truncatingIfNeeded: i))
        case .double(let d):
            // .NET TryGetValue<int> 对整值 double 成功
            if d == d.rounded(.towardZero), abs(d) <= Double(Int32.max) { return Int(d) }
            return nil
        case .string(let s): return Int32(s.trimmingCharacters(in: .whitespaces)).map(Int.init)
        default: return nil
        }
    }

    public static func getLong(_ node: JSONValue?) -> Int64? {
        guard let node else { return nil }
        switch node {
        case .int(let i): return i
        case .double(let d):
            if d == d.rounded(.towardZero), abs(d) < 9.2e18 { return Int64(d) }
            return nil
        case .string(let s): return Int64(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// 字符串原样；其它节点返回其 JSON 文本（数字 "41"、布尔 "true"、对象紧凑 JSON）。
    public static func getString(_ node: JSONValue?) -> String? {
        guard let node else { return nil }
        if case .string(let s) = node { return s }
        return JSONWriter.compact(node)
    }

    public static func getBool(_ node: JSONValue?) -> Bool? {
        guard let node else { return nil }
        if case .bool(let b) = node { return b }
        return nil
    }
}
