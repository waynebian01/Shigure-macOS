import Foundation

/// 条件表达式求值（对应 C# ModuleConditionEvaluator）。
/// 语法：`||` 外层、`&&` 内层纯文本切分；项为 `field op literal`、`field in (a, b)`、`field not in (...)`、`[!]field`。
public enum ConditionEvaluator {
    public struct Context: Sendable {
        public var failedSpells: [Int: Int64]?
        public var spellIndices: [Int64: Int]?
        public var itemIndices: [Int64: Int]?
        public var insertItems: [Int: Int64]?

        public init(failedSpells: [Int: Int64]? = nil, spellIndices: [Int64: Int]? = nil, itemIndices: [Int64: Int]? = nil, insertItems: [Int: Int64]? = nil) {
            self.failedSpells = failedSpells
            self.spellIndices = spellIndices
            self.itemIndices = itemIndices
            self.insertItems = insertItems
        }

        public static let empty = Context()
    }

    public enum Outcome: Sendable, Equatable {
        case matched(Bool)
        case error(String)
    }

    private static let inRegex = try! NSRegularExpression(pattern: #"^\s*(.+?)\s+(not\s+in|in)\s*\((.*?)\)\s*$"#, options: [.caseInsensitive])
    private static let comparisonRegex = try! NSRegularExpression(pattern: #"^\s*(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*$"#)
    private static let orSplit = try! NSRegularExpression(pattern: #"\s*\|\|\s*"#)
    private static let andSplit = try! NSRegularExpression(pattern: #"\s*&&\s*"#)
    private static let auraMemberRegex = try! NSRegularExpression(pattern: #"(?:^|\.)auras\.\d+\.(?:value|apps)$"#, options: [.caseInsensitive])

    public static func evaluate(_ expression: String?, state: GameState, context: Context = .empty) -> Outcome {
        guard let expression, !expression.isBlank else { return .matched(true) }
        for orPart in regexSplit(expression, orSplit) {
            var allAndMatched = true
            for andPart in regexSplit(orPart, andSplit) {
                switch evaluateTerm(andPart, state: state, context: context) {
                case .error(let e): return .error(e)
                case .matched(false):
                    allAndMatched = false
                case .matched(true): continue
                }
                if !allAndMatched { break }
            }
            if allAndMatched { return .matched(true) }
        }
        return .matched(false)
    }

    /// 整条规则：主条件成立 且 (无子条件 || 任一子条件成立)。
    public static func evaluateRule(_ rule: ModuleRule, state: GameState, context: Context = .empty) -> Outcome {
        switch evaluate(rule.condition, state: state, context: context) {
        case .error(let e): return .error(e)
        case .matched(false): return .matched(false)
        case .matched(true): break
        }
        guard let subs = rule.subConditions, !subs.isEmpty else { return .matched(true) }
        for sub in subs where !sub.isBlank {
            switch evaluate(sub, state: state, context: context) {
            case .error(let e): return .error(e)
            case .matched(true): return .matched(true)
            case .matched(false): continue
            }
        }
        return .matched(false)
    }

    public static func resolveInt(_ state: GameState, _ fieldName: String) -> Int? {
        guard let d = resolveDouble(state, fieldName), d.isFinite, abs(d) < 9.2e18 else { return nil }
        return Int(d.rounded(.towardZero))
    }

    public static func resolveDouble(_ state: GameState, _ fieldName: String) -> Double? {
        resolveValue(state, fieldName)?.doubleValue
    }

    // MARK: 项

    private static func evaluateTerm(_ term: String, state: GameState, context: Context) -> Outcome {
        let trimmed = term.trimmed()
        if trimmed.isEmpty { return .matched(true) }

        if let m = firstMatch(inRegex, trimmed) {
            let field = m[1].trimmed()
            if SpellIdConditionFields.contains(field) || ItemIdConditionFields.contains(field) {
                return .error("\(field) 仅支持 == 或 != 判断。")
            }
            let left = resolveValue(state, field, context: context)
            if left == nil && isStructuredSpellReference(field) { return .matched(false) }
            let op = normalizeOperator(m[2])
            let values = parseListLiterals(m[3])
            return compareIn(left, op, values)
        }

        guard let m = firstMatch(comparisonRegex, trimmed) else {
            let invert = trimmed.hasPrefix("!")
            let fieldName = invert ? String(trimmed.dropFirst()).trimmed() : trimmed
            let value = resolveValue(state, fieldName, context: context)
            if value == nil && isStructuredSpellReference(fieldName) { return .matched(false) }
            let truthy = value?.isTruthy ?? false
            return .matched(invert ? !truthy : truthy)
        }

        let field = m[1].trimmed()
        let left = resolveValue(state, field, context: context)
        if left == nil && isStructuredSpellReference(field) { return .matched(false) }
        let op = m[2]
        var right = parseLiteral(m[3].trimmed())
        if SpellIdConditionFields.contains(field) {
            guard op == "==" || op == "!=" else { return .error("\(field) 仅支持 == 或 != 判断。") }
            guard let spellId = right?.int64Value, let indices = context.spellIndices, let local = indices[spellId] else { return .matched(false) }
            right = .int(local)
        } else if ItemIdConditionFields.contains(field) {
            guard op == "==" || op == "!=" else { return .error("\(field) 仅支持 == 或 != 判断。") }
            guard let itemId = right?.int64Value, let indices = context.itemIndices, let local = indices[itemId] else { return .matched(false) }
            right = .int(local)
        }
        return .matched(compare(left, op, right))
    }

    static func isStructuredSpellReference(_ fieldName: String) -> Bool {
        if SpellFieldKey.parseSpell(fieldName) != nil || SpellFieldKey.parseAura(fieldName) != nil { return true }
        let key = SpellFieldKey.stripRoot(fieldName)
        return auraMemberRegex.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil
    }

    // MARK: 字段解析

    public static func resolveValue(_ state: GameState, _ fieldName: String, context: Context = .empty) -> StateValue? {
        var key = fieldName.trimmed()
        if let rest = key.dropPrefixIgnoringCase("state.") { key = rest }
        if let rest = key.dropPrefixIgnoringCase("spells.") { return state.spells[rest] ?? nil }
        if let rest = key.dropPrefixIgnoringCase("spell.") { return state.spells[rest] ?? nil }
        if let rest = key.dropPrefixIgnoringCase("auras.") { return state.auras[rest] ?? nil }
        if let rest = key.dropPrefixIgnoringCase("aura.") { return state.auras[rest] ?? nil }

        if ModuleSpecialActions.isFailedSpell(key) {
            return ModuleSpecialActions.failedSpell(in: state, map: context.failedSpells).map { .int(Int($0)) }
        }
        if ModuleSpecialActions.isFailedItem(key) {
            return ModuleSpecialActions.failedItem(in: state, map: context.insertItems).map { .int(Int($0)) }
        }

        if key.hasPrefixIgnoringCase("group.") {
            let parts = key.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3, let unit = state.group[parts[1]], let value = unit[parts[2]] {
                return value
            }
            return nil
        }

        if let counts = state.dynamicCounts, let count = counts[key] { return .int(count) }
        if let health = state.dynamicUnitHealth, let entry = health[key] { return entry }

        if let dot = key.firstIndex(of: "."), dot != key.startIndex, let units = state.dynamicUnits {
            let unitName = String(key[..<dot])
            if let slotEntry = units[unitName] {
                guard let slot = slotEntry else { return nil }
                let field = String(key[key.index(after: dot)...])
                if let member = state.group[slot], let value = member[field] { return value }
                return nil
            }
        }

        if let units = state.dynamicUnits, let bareSlot = units[key] {
            return .bool(bareSlot != nil)
        }

        if let dynamicValues = state.dynamicValues, let entry = dynamicValues[key] {
            return entry
        }

        return state.getValue(key)
    }

    // MARK: 字面量与比较

    public static func parseLiteral(_ value: String) -> StateValue? {
        let text = value.trimmed()
        if (text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2) || (text.hasPrefix("'") && text.hasSuffix("'") && text.count >= 2) {
            return .string(String(text.dropFirst().dropLast()))
        }
        switch text.lowercased() {
        case "null", "nil", "空": return nil
        case "true", "yes", "是": return .bool(true)
        case "false", "no", "否": return .bool(false)
        default:
            if let number = InvariantNumber.parseDouble(text) { return .double(number) }
            return .string(text)
        }
    }

    static func compare(_ left: StateValue?, _ op: String, _ right: StateValue?) -> Bool {
        if let l = left?.doubleValue, let r = right?.doubleValue {
            switch op {
            case "==": return l == r
            case "!=": return l != r
            case ">": return l > r
            case ">=": return l >= r
            case "<": return l < r
            case "<=": return l <= r
            default: return false
            }
        }
        if op == "==" || op == "!=" {
            let equal = (left?.comparableText ?? "").equalsIgnoringCase(right?.comparableText ?? "")
            return op == "==" ? equal : !equal
        }
        // 关系比较遇到非数字/缺失值不报错，视为不命中。
        return false
    }

    static func compareIn(_ left: StateValue?, _ op: String, _ values: [StateValue?]) -> Outcome {
        for value in values where compare(left, "==", value) {
            return .matched(op == "in")
        }
        return .matched(op == "not in")
    }

    static func parseListLiterals(_ value: String) -> [StateValue?] {
        splitList(value).map { $0.trimmed() }.filter { !$0.isEmpty }.map(parseLiteral)
    }

    static func splitList(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        for ch in value {
            if let q = quote {
                if ch == q { quote = nil }
                current.append(ch)
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
                continue
            }
            if ch == "," {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        result.append(current)
        return result
    }

    public static func normalizeOperator(_ op: String) -> String {
        op.trimmed().lowercased().collapsingWhitespace()
    }

    // MARK: 正则辅助

    static func firstMatch(_ regex: NSRegularExpression, _ text: String) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// .NET Regex.Split 语义：无匹配返回整段。
    static func regexSplit(_ text: String, _ regex: NSRegularExpression) -> [String] {
        var result: [String] = []
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(match.range, in: text) else { continue }
            result.append(String(text[last..<r.lowerBound]))
            last = r.upperBound
        }
        result.append(String(text[last...]))
        return result
    }
}

/// 条件文本 ⇄ 可视化项（对应 C# ConditionExpression）。
public struct ConditionTerm: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var field: String
    public var op: String
    public var value: String
    /// 与前一项的连接：true = 或（新的 OR 组开头），false = 且。
    public var orWithPrevious: Bool

    public init(field: String, op: String, value: String, orWithPrevious: Bool = false) {
        self.field = field
        self.op = op
        self.value = value
        self.orWithPrevious = orWithPrevious
    }

    public static func == (lhs: ConditionTerm, rhs: ConditionTerm) -> Bool {
        lhs.field == rhs.field && lhs.op == rhs.op && lhs.value == rhs.value && lhs.orWithPrevious == rhs.orWithPrevious
    }
}

public enum ConditionExpression {
    private static let inRegex = try! NSRegularExpression(pattern: #"^\s*(.+?)\s+(not\s+in|in)\s*\((.*?)\)\s*$"#, options: [.caseInsensitive])
    private static let comparisonRegex = try! NSRegularExpression(pattern: #"^\s*(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+?)\s*$"#)
    private static let orSplit = try! NSRegularExpression(pattern: #"\s*\|\|\s*"#)
    private static let andSplit = try! NSRegularExpression(pattern: #"\s*&&\s*"#)

    public static func parse(_ expression: String) -> [ConditionTerm] {
        var terms: [ConditionTerm] = []
        if expression.isBlank { return terms }
        for (orIndex, orPart) in ConditionEvaluator.regexSplit(expression, orSplit).enumerated() {
            for (andIndex, andPart) in ConditionEvaluator.regexSplit(orPart, andSplit).enumerated() {
                let trimmed = andPart.trimmed()
                if trimmed.isEmpty { continue }
                var term: ConditionTerm
                if let m = ConditionEvaluator.firstMatch(inRegex, trimmed) {
                    term = ConditionTerm(field: m[1].trimmed(), op: ConditionEvaluator.normalizeOperator(m[2]), value: m[3].trimmed())
                } else if let m = ConditionEvaluator.firstMatch(comparisonRegex, trimmed) {
                    term = ConditionTerm(field: m[1].trimmed(), op: m[2], value: m[3].trimmed())
                } else if trimmed.hasPrefix("!") {
                    term = ConditionTerm(field: String(trimmed.dropFirst()).trimmed(), op: "==", value: "false")
                } else {
                    term = ConditionTerm(field: trimmed, op: "==", value: "true")
                }
                term.orWithPrevious = orIndex > 0 && andIndex == 0
                terms.append(term)
            }
        }
        return terms
    }

    public static func build(_ terms: [ConditionTerm]) -> String {
        var result = ""
        var first = true
        for term in terms {
            let field = term.field.trimmed()
            let value = term.value.trimmed()
            if field.isEmpty || value.isEmpty { continue }
            let op = term.op.trimmed()
            let text: String
            if op == "in" || op == "not in" {
                let inner = value.hasPrefix("(") && value.hasSuffix(")") ? String(value.dropFirst().dropLast()) : value
                text = "\(field) \(op) (\(inner))"
            } else {
                text = "\(field) \(op) \(value)"
            }
            if first {
                result = text
                first = false
            } else {
                result += (term.orWithPrevious ? " || " : " && ") + text
            }
        }
        return result
    }
}
