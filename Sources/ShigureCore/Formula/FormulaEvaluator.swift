import Foundation

/// 公式动态数值求值：`+ - * /`、括号、一元正负、int/round/floor/ceil/min/max、比较运算符。
public enum FormulaEvaluator {
    public struct FormulaError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { message }
    }

    public static func evaluateInt(_ expression: String?, state: GameState) -> Result<Int, FormulaError> {
        let normalized = normalizeExpression(expression)
        if normalized.isBlank { return .failure(FormulaError(message: "公式为空。")) }
        do {
            var parser = Parser(text: Array(normalized), state: state)
            let result = try parser.parse()
            if result.isNaN || result.isInfinite { return .failure(FormulaError(message: "公式结果不是有效数字。")) }
            guard abs(result) < 9.2e18 else { return .failure(FormulaError(message: "公式结果不是有效数字。")) }
            return .success(Int(result.rounded(.towardZero)))
        } catch let error as FormulaError {
            return .failure(error)
        } catch {
            return .failure(FormulaError(message: "\(error)"))
        }
    }

    /// 判断公式是否为布尔表达式（包含顶层比较运算符）。
    public static func isBooleanExpression(_ expression: String?) -> Bool {
        let normalized = normalizeExpression(expression)
        if normalized.isBlank { return false }

        var depth = 0
        var i = 0
        let chars = Array(normalized)

        while i < chars.count {
            let c = chars[i]
            let openParen: Character = "("
            let closeParen: Character = ")"
            let gt: Character = ">"
            let lt: Character = "<"
            let eq: Character = "="
            let exclaim: Character = "!"

            if c == openParen { depth += 1 }
            else if c == closeParen { depth -= 1 }
            else if depth == 0 {
                if i + 1 < chars.count {
                    let next = chars[i + 1]
                    if (c == eq && next == eq) || (c == exclaim && next == eq) ||
                       (c == gt && next == eq) || (c == lt && next == eq) {
                        return true
                    }
                }
                if (c == gt || c == lt) && (i + 1 >= chars.count || chars[i + 1] != eq) {
                    return true
                }
            }
            i += 1
        }

        return false
    }

    /// 去掉 `#` 注释；若含 `名称 = 表达式`，只保留表达式。
    public static func normalizeExpression(_ expression: String?) -> String {
        let text = stripComment(expression).trimmed()
        if let eq = text.firstIndex(of: "="), eq > text.startIndex, text.index(after: eq) < text.endIndex {
            return String(text[text.index(after: eq)...]).trimmed()
        }
        return text
    }

    public static func splitAssignment(_ expression: String?) -> (field: String, formula: String)? {
        let formula = normalizeExpression(expression)
        let text = stripComment(expression).trimmed()
        guard let eq = text.firstIndex(of: "="), eq > text.startIndex, text.index(after: eq) < text.endIndex else { return nil }
        let field = String(text[..<eq]).trimmed()
        guard !field.isEmpty, !formula.isEmpty else { return nil }
        return (field, formula)
    }

    static func stripComment(_ expression: String?) -> String {
        let text = expression ?? ""
        guard let hash = text.firstIndex(of: "#") else { return text }
        return String(text[..<hash])
    }

    private struct Parser {
        let text: [Character]
        let state: GameState
        var position = 0

        init(text: [Character], state: GameState) {
            self.text = text
            self.state = state
        }

        var isEnd: Bool { position >= text.count }
        var current: Character { isEnd ? "\0" : text[position] }

        mutating func parse() throws -> Double {
            let value = try parseComparison()
            skipWhitespace()
            if !isEnd { throw error("无法识别\"\(current)\"。") }
            return value
        }

        mutating func parseComparison() throws -> Double {
            let left = try parseAdditive()
            skipWhitespace()

            if matchString("==") {
                let right = try parseAdditive()
                return left == right ? 1.0 : 0.0
            } else if matchString("!=") {
                let right = try parseAdditive()
                return left != right ? 1.0 : 0.0
            } else if matchString(">=") {
                let right = try parseAdditive()
                return left >= right ? 1.0 : 0.0
            } else if matchString("<=") {
                let right = try parseAdditive()
                return left <= right ? 1.0 : 0.0
            } else if current == ">" && !peekEquals() {
                position += 1
                let right = try parseAdditive()
                return left > right ? 1.0 : 0.0
            } else if current == "<" && !peekEquals() {
                position += 1
                let right = try parseAdditive()
                return left < right ? 1.0 : 0.0
            }

            return left
        }

        mutating func parseAdditive() throws -> Double {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if match("+") { value += try parseTerm() }
                else if match("-") { value -= try parseTerm() }
                else { return value }
            }
        }

        mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while true {
                skipWhitespace()
                if match("*") {
                    value *= try parseFactor()
                } else if match("/") {
                    let divisor = try parseFactor()
                    if abs(divisor) < Double.ulpOfOne { throw error("公式中出现除以 0。") }
                    value /= divisor
                } else {
                    return value
                }
            }
        }

        mutating func parseFactor() throws -> Double {
            skipWhitespace()
            if match("+") { return try parseFactor() }
            if match("-") { return -(try parseFactor()) }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if match("(") {
                let value = try parseComparison()
                try require(")")
                return value
            }
            if current.isASCIIDigit || current == "." { return try parseNumber() }
            if Self.isIdentifierStart(current) {
                let name = parseIdentifier()
                skipWhitespace()
                return match("(") ? try parseFunction(name) : try resolveField(name)
            }
            throw error("公式不完整。")
        }

        mutating func parseFunction(_ name: String) throws -> Double {
            var args: [Double] = []
            skipWhitespace()
            if !match(")") {
                while true {
                    args.append(try parseComparison())
                    skipWhitespace()
                    if match(")") { break }
                    try require(",")
                }
            }
            switch name.lowercased() {
            case "int" where args.count == 1: return Double(Int(args[0].rounded(.towardZero)))
            case "round" where args.count == 1: return args[0].rounded(.toNearestOrEven) // Math.Round 银行家舍入
            case "floor" where args.count == 1: return args[0].rounded(.down)
            case "ceil" where args.count == 1: return args[0].rounded(.up)
            case "min" where !args.isEmpty: return args.min()!
            case "max" where !args.isEmpty: return args.max()!
            default: throw error("不支持函数\"\(name)\"。")
            }
        }

        mutating func parseNumber() throws -> Double {
            let start = position
            while current.isASCIIDigit || current == "." { position += 1 }
            let text = String(self.text[start..<position])
            guard let number = InvariantNumber.parseDouble(text) else { throw error("数字\"\(text)\"无效。") }
            return number
        }

        mutating func parseIdentifier() -> String {
            let start = position
            while Self.isIdentifierPart(current) { position += 1 }
            return String(text[start..<position]).trimmed()
        }

        func resolveField(_ name: String) throws -> Double {
            if let value = ConditionEvaluator.resolveDouble(state, name) { return value }
            throw error("无法读取数值\"\(name)\"。")
        }

        mutating func require(_ expected: Character) throws {
            skipWhitespace()
            if !match(expected) { throw error("缺少\"\(expected)\"。") }
        }

        mutating func match(_ expected: Character) -> Bool {
            guard current == expected else { return false }
            position += 1
            return true
        }

        mutating func matchString(_ expected: String) -> Bool {
            let chars = Array(expected)
            guard position + chars.count <= text.count else { return false }
            for i in 0..<chars.count {
                if text[position + i] != chars[i] { return false }
            }
            position += chars.count
            return true
        }

        func peekEquals() -> Bool {
            let equalsChar: Character = "="
            guard position + 1 < text.count else { return false }
            return text[position + 1] == equalsChar
        }

        mutating func skipWhitespace() {
            while !isEnd, current.isWhitespace { position += 1 }
        }

        func error(_ message: String) -> FormulaError {
            FormulaError(message: "\(message) 位置: \(position + 1)")
        }

        static func isIdentifierStart(_ c: Character) -> Bool {
            c == "_" || c == "$" || c.isLetter || isCJK(c)
        }

        static func isIdentifierPart(_ c: Character) -> Bool {
            isIdentifierStart(c) || c.isASCIIDigit || c == "."
        }

        static func isCJK(_ c: Character) -> Bool {
            guard let scalar = c.unicodeScalars.first else { return false }
            return scalar.value >= 0x3400 && scalar.value <= 0x9FFF
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
