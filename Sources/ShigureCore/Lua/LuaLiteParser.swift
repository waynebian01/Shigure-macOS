import Foundation

/// Lua 表键：数字键截断为 Int64，字符串键，布尔键。
public enum LuaKey: Hashable, Sendable, CustomStringConvertible {
    case int(Int64)
    case string(String)
    case bool(Bool)

    public var intValue: Int64? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var description: String {
        switch self {
        case .int(let i): return String(i)
        case .string(let s): return s
        case .bool(let b): return String(b)
        }
    }
}

public indirect enum LuaValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case table(LuaTable)

    public var tableValue: LuaTable? {
        if case .table(let t) = self { return t }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// NumberValue.AsInt：向零截断。
    public var intValue: Int64? {
        guard case .number(let n) = self, n.isFinite else { return nil }
        return Int64(n.rounded(.towardZero))
    }
}

/// 保持声明顺序的 Lua 表。位置项键为 nil（仅出现在 entries 中；ipairs 走 map）。
public struct LuaTable: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let key: LuaKey?
        public let value: LuaValue
    }

    public private(set) var entries: [Entry] = []
    private var map: [LuaKey: LuaValue] = [:]
    private var trailingComments: [LuaKey: String] = [:]

    public init() {}

    public mutating func set(_ key: LuaKey?, _ value: LuaValue, trailingComment: String? = nil) {
        guard let key else {
            entries.append(Entry(key: nil, value: value))
            return
        }
        map[key] = value
        entries.append(Entry(key: key, value: value))
        if let comment = trailingComment, !comment.isBlank {
            trailingComments[key] = comment.trimmed()
        }
    }

    public func get(_ key: LuaKey) -> LuaValue? { map[key] }
    public func get(_ key: String) -> LuaValue? { map[.string(key)] }
    public func get(_ index: Int64) -> LuaValue? { map[.int(index)] }

    public func trailingComment(_ key: LuaKey) -> String? { trailingComments[key] }
    public func trailingComment(_ index: Int64) -> String? { trailingComments[.int(index)] }

    /// 从 1 起连续枚举到首个缺失下标。
    public func ipairs() -> [LuaValue] {
        var result: [LuaValue] = []
        var i: Int64 = 1
        while let value = map[.int(i)] {
            result.append(value)
            i += 1
        }
        return result
    }

    public func string(_ key: String) -> String? { get(key)?.stringValue }
    public func number(_ key: String) -> Double? { get(key)?.numberValue }
    public func bool(_ key: String) -> Bool? { get(key)?.boolValue }
    public func table(_ key: String) -> LuaTable? { get(key)?.tableValue }
    public func table(_ index: Int64) -> LuaTable? { get(index)?.tableValue }
}

public struct LuaParseError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public var description: String { message }
}

/// 轻量 Lua 表字面量解析：足够读取 Senkoh ClassBlocks / ClassMacros 声明。
public enum LuaLiteParser {
    public struct Extracted: Sendable {
        public let table: LuaTable
        /// 表字面量在源码中的起止（UTF-16 偏移，含首尾大括号；end 为 exclusive）。
        public let tableStart: Int
        public let tableEndExclusive: Int
    }

    public static func extractAssignedTable(_ source: String, _ assignmentName: String) -> LuaTable? {
        try? extract(source, assignmentName)?.table
    }

    /// 定位 `name = { ... }`，解析并返回表与字符区间，用于 round-trip 替换。
    public static func extract(_ source: String, _ assignmentName: String) throws -> Extracted? {
        let text = Array(source.utf16)
        let name = Array(assignmentName.utf16)
        guard let index = find(name, in: text, from: 0) else { return nil }
        guard let eq = text[(index + name.count)...].firstIndex(of: u("=")) else { return nil }
        var cursor = eq + 1
        while cursor < text.count, isWhitespace(text[cursor]) { cursor += 1 }
        guard cursor < text.count, text[cursor] == u("{") else { return nil }
        var parser = Parser(text: text, pos: cursor)
        guard case .table(let table) = try parser.parseValue() else { return nil }
        return Extracted(table: table, tableStart: cursor, tableEndExclusive: parser.pos)
    }

    /// 用新的表字面量替换源码中的对应区间（区间为 UTF-16 偏移）。
    public static func replaceRange(in source: String, start: Int, endExclusive: Int, with replacement: String) -> String {
        let utf16 = source.utf16
        let s = utf16.index(utf16.startIndex, offsetBy: start)
        let e = utf16.index(utf16.startIndex, offsetBy: endExclusive)
        return String(utf16[utf16.startIndex..<s])! + replacement + String(utf16[e...])!
    }

    private static func find(_ needle: [UInt16], in text: [UInt16], from: Int) -> Int? {
        guard !needle.isEmpty, text.count >= needle.count else { return nil }
        var i = from
        while i + needle.count <= text.count {
            if text[i] == needle[0] && Array(text[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }

    static func isWhitespace(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B || c == 0x0C
    }

    static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

    static func isLetter(_ c: UInt16) -> Bool {
        if let scalar = Unicode.Scalar(c) { return scalar.properties.isAlphabetic }
        return true // 代理对（CJK 扩展）按字母处理
    }

    struct Parser {
        let text: [UInt16]
        var pos: Int

        init(text: [UInt16], pos: Int) {
            self.text = text
            self.pos = pos
        }

        var current: UInt16? { pos < text.count ? text[pos] : nil }

        mutating func parseValue() throws -> LuaValue {
            skipTrivia()
            guard let ch = current else { return .null }
            if ch == u("{") { return .table(try parseTable()) }
            if ch == u("\"") || ch == u("'") { return .string(try parseQuotedString()) }
            if ch == u("-") || isDigit(ch) { return try parseNumber() }
            if isLetter(ch) || ch == u("_") {
                let ident = parseIdentifier()
                switch ident {
                case "true": return .bool(true)
                case "false": return .bool(false)
                case "nil": return .null
                default: return .string(ident)
                }
            }
            throw LuaParseError(message: "无法解析的 Lua 值，位置 \(pos): '\(String(decoding: [ch], as: UTF16.self))'")
        }

        mutating func parseTable() throws -> LuaTable {
            try expect(u("{"))
            var table = LuaTable()
            var nextArrayIndex: Int64 = 1
            while true {
                skipTrivia()
                guard let ch = current else { throw LuaParseError(message: "Lua 表缺少结束 }") }
                if ch == u("}") { pos += 1; break }

                var key: LuaKey?
                var value: LuaValue
                if ch == u("[") {
                    pos += 1
                    skipTrivia()
                    let keyValue = try parseValue()
                    skipTrivia()
                    try expect(u("]"))
                    skipTrivia()
                    try expect(u("="))
                    key = try toKey(keyValue)
                    value = try parseValue()
                } else {
                    let start = pos
                    let peeked = try parseValue()
                    skipTrivia()
                    if current == u("="), case .string(let name) = peeked, isIdentifierAt(start) {
                        pos += 1
                        key = .string(name)
                        value = try parseValue()
                    } else {
                        key = .int(nextArrayIndex)
                        nextArrayIndex += 1
                        value = peeked
                    }
                }
                let comment = captureEntryTrailingComment()
                table.set(key, value, trailingComment: comment)
            }
            return table
        }

        /// 读取表项值后的分隔符与同行 `--` 注释（`value, -- 名称` 或 `value -- 名称`）。
        mutating func captureEntryTrailingComment() -> String? {
            skipSpacesAndTabs()
            var comment: String?
            if let before = tryReadLineComment() { comment = before }
            skipTrivia()
            if let c = current, c == u(",") || c == u(";") {
                pos += 1
                skipSpacesAndTabs()
                if comment == nil, let after = tryReadLineComment() { comment = after }
            }
            guard let comment, !comment.isBlank else { return nil }
            return comment.trimmed()
        }

        mutating func skipSpacesAndTabs() {
            while let c = current, c == 0x20 || c == 0x09 { pos += 1 }
        }

        mutating func tryReadLineComment() -> String? {
            guard pos + 1 < text.count, text[pos] == u("-"), text[pos + 1] == u("-") else { return nil }
            if pos + 3 < text.count, text[pos + 2] == u("["), text[pos + 3] == u("[") { return nil }
            pos += 2
            let start = pos
            while let c = current, c != 0x0A, c != 0x0D { pos += 1 }
            return String(decoding: Array(text[start..<pos]), as: UTF16.self)
        }

        func isIdentifierAt(_ start: Int) -> Bool {
            guard start >= 0, start < text.count else { return false }
            let ch = text[start]
            return isLetter(ch) || ch == u("_")
        }

        func toKey(_ value: LuaValue) throws -> LuaKey {
            switch value {
            case .number(let n): return .int(Int64(n.rounded(.towardZero)))
            case .string(let s): return .string(s)
            case .bool(let b): return .bool(b)
            default: throw LuaParseError(message: "不支持的表键类型")
            }
        }

        mutating func parseQuotedString() throws -> String {
            let quote = text[pos]
            pos += 1
            var units: [UInt16] = []
            while pos < text.count {
                let ch = text[pos]
                pos += 1
                if ch == quote { return String(decoding: units, as: UTF16.self) }
                if ch == u("\\"), pos < text.count {
                    let esc = text[pos]
                    pos += 1
                    switch esc {
                    case u("n"): units.append(0x0A)
                    case u("r"): units.append(0x0D)
                    case u("t"): units.append(0x09)
                    default: units.append(esc)
                    }
                    continue
                }
                units.append(ch)
            }
            throw LuaParseError(message: "字符串未闭合")
        }

        mutating func parseNumber() throws -> LuaValue {
            let start = pos
            if text[pos] == u("-") { pos += 1 }
            while pos < text.count {
                let c = text[pos]
                let isSign = c == u("+") || c == u("-")
                let isExp = c == u("e") || c == u("E")
                if isSign {
                    if pos == start { break }
                    let prev = text[pos - 1]
                    if !(prev == u("e") || prev == u("E")) { break }
                }
                if isDigit(c) || c == u(".") || isExp || isSign {
                    pos += 1
                    continue
                }
                break
            }
            let str = String(decoding: Array(text[start..<pos]), as: UTF16.self)
            guard let number = Double(str) else { throw LuaParseError(message: "无法解析数字: \(str)") }
            return .number(number)
        }

        mutating func parseIdentifier() -> String {
            let start = pos
            pos += 1
            while pos < text.count {
                let ch = text[pos]
                if isLetter(ch) || isDigit(ch) || ch == u("_") { pos += 1; continue }
                break
            }
            return String(decoding: Array(text[start..<pos]), as: UTF16.self)
        }

        mutating func expect(_ expected: UInt16) throws {
            skipTrivia()
            guard let c = current, c == expected else {
                throw LuaParseError(message: "期望 '\(String(decoding: [expected], as: UTF16.self))'，位置 \(pos)")
            }
            pos += 1
        }

        mutating func skipTrivia() {
            while pos < text.count {
                let c = text[pos]
                if isWhitespace(c) { pos += 1; continue }
                if c == u("-"), pos + 1 < text.count, text[pos + 1] == u("-") {
                    pos += 2
                    if pos + 1 < text.count, text[pos] == u("["), text[pos + 1] == u("[") {
                        pos += 2
                        while pos + 1 < text.count, !(text[pos] == u("]") && text[pos + 1] == u("]")) { pos += 1 }
                        if pos + 1 < text.count { pos += 2 }
                        continue
                    }
                    while pos < text.count, text[pos] != 0x0A, text[pos] != 0x0D { pos += 1 }
                    continue
                }
                break
            }
        }
    }
}

@inline(__always)
func u(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }
