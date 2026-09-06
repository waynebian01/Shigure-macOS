import Foundation

public enum SpellFieldKey {
    public static let auraValue = "value"
    public static let auraApplications = "apps"
    public static let spellCooldown = "cooldown"
    public static let spellChargeCooldown = "chargeCooldown"
    public static let spellCount = "count"

    public static func aura(scope: String, spellId: Int64, metric: String = auraValue) -> String {
        "auras.\(scope).\(spellId).\(metric)"
    }

    public static func auraMember(spellId: Int64, metric: String = auraValue) -> String {
        "auras.\(spellId).\(metric)"
    }

    public static func spell(spellId: Int64, metric: String = spellCooldown) -> String {
        "spells.\(spellId).\(metric)"
    }

    public static func stripRoot(_ value: String) -> String {
        let key = value.trimmed()
        return key.dropPrefixIgnoringCase("state.") ?? key
    }

    private static func parts(of value: String) -> [String] {
        stripRoot(value).split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `spells.<id>.<metric>`，恰好 3 段，id > 0。
    public static func parseSpell(_ value: String?) -> (spellId: Int64, metric: String)? {
        let p = parts(of: value ?? "")
        guard p.count == 3, p[0].equalsIgnoringCase("spells"), let id = InvariantNumber.parseInt64(p[1]), id > 0 else { return nil }
        return (id, p[2])
    }

    /// `auras.<scope...>.<id>.<metric>`，至少 4 段。
    public static func parseAura(_ value: String?) -> (scope: String, spellId: Int64, metric: String)? {
        let p = parts(of: value ?? "")
        guard p.count >= 4, p[0].equalsIgnoringCase("auras"),
              let id = InvariantNumber.parseInt64(p[p.count - 2]), id > 0 else { return nil }
        return (p[1..<(p.count - 2)].joined(separator: "."), id, p[p.count - 1])
    }

    /// 队伍成员形式 `auras.<id>.<metric>`；若 "auras." 出现在中间（如 单位名.auras.x.value）则从该处截取。
    public static func parseAuraMember(_ value: String?) -> (spellId: Int64, metric: String)? {
        var key = stripRoot(value ?? "")
        if let range = key.range(of: "auras.", options: [.caseInsensitive]), range.lowerBound != key.startIndex {
            key = String(key[range.lowerBound...])
        }
        let p = key.split(separator: ".", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard p.count == 3, p[0].equalsIgnoringCase("auras"), let id = InvariantNumber.parseInt64(p[1]), id > 0 else { return nil }
        return (id, p[2])
    }

    public static func canonicalAuraId(spellId: Int64?, spellIds: [Int64]?) -> Int64? {
        if let spellId, spellId > 0 { return spellId }
        let ids = Set((spellIds ?? []).filter { $0 > 0 })
        return ids.min()
    }
}
