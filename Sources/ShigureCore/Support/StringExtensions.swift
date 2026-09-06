import Foundation

public extension String {
    var isBlank: Bool { allSatisfy(\.isWhitespace) }

    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func hasPrefixIgnoringCase(_ prefix: String) -> Bool {
        guard count >= prefix.count else { return false }
        return self[startIndex..<index(startIndex, offsetBy: prefix.count)].caseInsensitiveCompare(prefix) == .orderedSame
    }

    func hasSuffixIgnoringCase(_ suffix: String) -> Bool {
        guard count >= suffix.count else { return false }
        return self[index(endIndex, offsetBy: -suffix.count)...].caseInsensitiveCompare(suffix) == .orderedSame
    }

    func dropPrefixIgnoringCase(_ prefix: String) -> String? {
        guard hasPrefixIgnoringCase(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func equalsIgnoringCase(_ other: String) -> Bool {
        caseInsensitiveCompare(other) == .orderedSame
    }

    /// 按空白折叠为单个空格并两端修剪（.NET Regex.Replace(@"\s+", " ")）。
    func collapsingWhitespace() -> String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public extension Optional where Wrapped == String {
    var isNilOrBlank: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isBlank
        }
    }
}

/// .NET 不变文化整数/浮点解析（只接受 ASCII 数字、可选正负号、小数点、指数）。
enum InvariantNumber {
    static func parseInt(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return Int(t)
    }

    static func parseInt64(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return Int64(t)
    }

    static func parseDouble(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        // Double(String) 接受 "inf"/"nan"/十六进制，这里限制为十进制文本。
        let allowed = Set("0123456789+-.eE")
        guard t.allSatisfy({ allowed.contains($0) }) else { return nil }
        return Double(t)
    }
}
