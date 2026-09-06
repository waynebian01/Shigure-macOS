import Foundation

public struct NamedId: Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public enum ClassNames {
    private static let classes: [Int: String] = [
        1: "战士", 2: "圣骑士", 3: "猎人", 4: "潜行者", 5: "牧师", 6: "死亡骑士", 7: "萨满祭司",
        8: "法师", 9: "术士", 10: "武僧", 11: "德鲁伊", 12: "恶魔猎手", 13: "唤魔师"
    ]

    /// config/ 职业文件名（不含扩展名），PascalCase 英文名。
    private static let configFileNames: [Int: String] = [
        1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 6: "DeathKnight", 7: "Shaman",
        8: "Mage", 9: "Warlock", 10: "Monk", 11: "Druid", 12: "DemonHunter", 13: "Evoker"
    ]

    private struct SpecKey: Hashable { let classId: Int; let specId: Int }
    private struct TalentKey: Hashable { let classId: Int; let specId: Int; let talentId: Int }

    private static let specs: [SpecKey: String] = {
        let table: [(Int, Int, String)] = [
            (1, 1, "武器"), (1, 2, "狂怒"), (1, 3, "防护"),
            (2, 1, "神圣"), (2, 2, "防护"), (2, 3, "惩戒"),
            (3, 1, "野兽控制"), (3, 2, "射击"), (3, 3, "生存"),
            (4, 1, "奇袭"), (4, 2, "狂徒"), (4, 3, "敏锐"),
            (5, 1, "戒律"), (5, 2, "神圣"), (5, 3, "暗影"),
            (6, 1, "鲜血"), (6, 2, "冰霜"), (6, 3, "邪恶"),
            (7, 1, "元素"), (7, 2, "增强"), (7, 3, "恢复"),
            (8, 1, "奥术"), (8, 2, "火焰"), (8, 3, "冰霜"),
            (9, 1, "痛苦"), (9, 2, "恶魔学识"), (9, 3, "毁灭"),
            (10, 1, "酒仙"), (10, 2, "织雾"), (10, 3, "踏风"),
            (11, 1, "平衡"), (11, 2, "野性"), (11, 3, "守护"), (11, 4, "恢复"),
            (12, 1, "浩劫"), (12, 2, "复仇"), (12, 3, "噬灭"),
            (13, 1, "湮灭"), (13, 2, "恩护"), (13, 3, "增辉")
        ]
        var result: [SpecKey: String] = [:]
        for (c, s, name) in table { result[SpecKey(classId: c, specId: s)] = name }
        return result
    }()

    private static let specIconFileNames: [SpecKey: String] = {
        let table: [(Int, Int, String)] = [
            (1, 1, "warrior-arms"), (1, 2, "warrior-fury"), (1, 3, "warrior-protection"),
            (2, 1, "paladin-holy"), (2, 2, "paladin-protection"), (2, 3, "paladin-retribution"),
            (3, 1, "hunter-beastmastery"), (3, 2, "hunter-marksmanship"), (3, 3, "hunter-survival"),
            (4, 1, "rogue-assassination"), (4, 2, "rogue-outlaw"), (4, 3, "rogue-subtlety"),
            (5, 1, "priest-discipline"), (5, 2, "priest-holy"), (5, 3, "priest-shadow"),
            (6, 1, "deathknight-blood"), (6, 2, "deathknight-frost"), (6, 3, "deathknight-unholy"),
            (7, 1, "shaman-elemental"), (7, 2, "shaman-enhancement"), (7, 3, "shaman-restoration"),
            (8, 1, "mage-arcane"), (8, 2, "mage-fire"), (8, 3, "mage-frost"),
            (9, 1, "warlock-affliction"), (9, 2, "warlock-demonology"), (9, 3, "warlock-destruction"),
            (10, 1, "monk-brewmaster"), (10, 2, "monk-mistweaver"), (10, 3, "monk-windwalker"),
            (11, 1, "druid-balance"), (11, 2, "druid-feral"), (11, 3, "druid-guardian"), (11, 4, "druid-restoration"),
            (12, 1, "demonhunter-havoc"), (12, 2, "demonhunter-vengeance"), (12, 3, "demonhunter-devourer"),
            (13, 1, "evoker-devastation"), (13, 2, "evoker-preservation"), (13, 3, "evoker-augmentation")
        ]
        var result: [SpecKey: String] = [:]
        for (c, s, name) in table { result[SpecKey(classId: c, specId: s)] = name }
        return result
    }()

    private static let heroTalents: [TalentKey: String] = {
        let table: [(Int, Int, Int, String)] = [
            (1, 1, 1, "巨神兵"), (1, 1, 2, "屠戮者"), (1, 2, 2, "屠戮者"), (1, 2, 3, "山丘领主"), (1, 3, 1, "巨神兵"), (1, 3, 3, "山丘领主"),
            (2, 1, 1, "烈日先驱"), (2, 1, 2, "铸光者"), (2, 2, 2, "铸光者"), (2, 2, 3, "圣殿骑士"), (2, 3, 1, "烈日先驱"), (2, 3, 3, "圣殿骑士"),
            (3, 1, 1, "黑暗游侠"), (3, 1, 2, "猎群领袖"), (3, 2, 1, "黑暗游侠"), (3, 2, 3, "哨兵"), (3, 3, 1, "猎群领袖"), (3, 3, 3, "哨兵"),
            (4, 1, 1, "死亡猎手"), (4, 1, 2, "命缚者"), (4, 2, 1, "命缚者"), (4, 2, 3, "欺诈者"), (4, 3, 1, "死亡猎手"), (4, 3, 3, "欺诈者"),
            (5, 1, 1, "神谕者"), (5, 1, 2, "虚空编织者"), (5, 2, 1, "神谕者"), (5, 2, 3, "执政官"), (5, 3, 3, "执政官"), (5, 3, 2, "虚空编织者"),
            (6, 1, 1, "死亡使者"), (6, 1, 2, "萨莱因"), (6, 2, 1, "死亡使者"), (6, 2, 3, "天启骑士"), (6, 3, 3, "天启骑士"), (6, 3, 2, "萨莱因"),
            (7, 1, 1, "先知"), (7, 1, 2, "风暴使者"), (7, 2, 2, "风暴使者"), (7, 2, 3, "图腾祭祀"), (7, 3, 1, "先知"), (7, 3, 3, "图腾祭祀"),
            (8, 1, 1, "疾咒师"), (8, 1, 2, "日怒"), (8, 2, 3, "霜火"), (8, 2, 2, "日怒"), (8, 3, 3, "霜火"), (8, 3, 2, "疾咒师"),
            (9, 1, 1, "地狱召唤者"), (9, 1, 2, "灵魂收割者"), (9, 2, 3, "恶魔使徒"), (9, 2, 2, "灵魂收割者"), (9, 3, 3, "恶魔使徒"), (9, 3, 2, "地狱召唤者"),
            (10, 1, 1, "祥和宗师"), (10, 1, 2, "影踪派"), (10, 2, 3, "天神御师"), (10, 2, 2, "祥和宗师"), (10, 3, 3, "天神御师"), (10, 3, 2, "影踪派"),
            (11, 1, 1, "艾露恩钦选者"), (11, 1, 2, "丛林守护者"), (11, 2, 3, "利爪德鲁伊"), (11, 2, 4, "荒野追猎者"), (11, 3, 3, "利爪德鲁伊"), (11, 3, 2, "艾露恩钦选者"), (11, 4, 2, "丛林守护者"), (11, 4, 4, "荒野追猎者"),
            (12, 1, 1, "奥达奇收割者"), (12, 1, 2, "邪痕枭雄"), (12, 2, 1, "奥达奇收割者"), (12, 2, 3, "歼灭者"), (12, 3, 3, "歼灭者"), (12, 3, 2, "虚痕枭雄"),
            (13, 1, 1, "塑焰者"), (13, 1, 2, "鳞长"), (13, 2, 3, "时空守卫"), (13, 2, 2, "塑焰者"), (13, 3, 3, "时空守卫"), (13, 3, 2, "鳞长")
        ]
        var result: [TalentKey: String] = [:]
        for (c, s, t, name) in table { result[TalentKey(classId: c, specId: s, talentId: t)] = name }
        return result
    }()

    public static func classAndSpecName(classId: Int?, specId: Int?) -> (className: String?, specName: String?) {
        guard let classId, classId != 0 else { return (nil, nil) }
        let className = classes[classId] ?? "职业\(classId)"
        guard let specId, specId != 0 else { return (className, nil) }
        let specName = specs[SpecKey(classId: classId, specId: specId)] ?? "专精\(specId)"
        return (className, specName)
    }

    public static func className(_ classId: Int) -> String? { classes[classId] }

    public static func specName(classId: Int, specId: Int) -> String? {
        specs[SpecKey(classId: classId, specId: specId)]
    }

    public static var allClasses: [NamedId] {
        classes.keys.sorted().map { NamedId(id: $0, name: classes[$0]!) }
    }

    public static func configFileName(_ classId: Int) -> String {
        configFileNames[classId] ?? String(classId)
    }

    public static func classId(forConfigFileName name: String) -> Int? {
        configFileNames.first { $0.value.equalsIgnoringCase(name) }?.key
    }

    public static func specs(of classId: Int) -> [NamedId] {
        specs.filter { $0.key.classId == classId }
            .sorted { $0.key.specId < $1.key.specId }
            .map { NamedId(id: $0.key.specId, name: $0.value) }
    }

    public static func specIconFileName(classId: Int, specId: Int) -> String? {
        specIconFileNames[SpecKey(classId: classId, specId: specId)]
    }

    public static func heroTalents(classId: Int, specId: Int) -> [NamedId] {
        heroTalents.filter { $0.key.classId == classId && $0.key.specId == specId }
            .sorted { $0.key.talentId < $1.key.talentId }
            .map { NamedId(id: $0.key.talentId, name: $0.value) }
    }

    public static func heroTalentName(classId: Int, specId: Int, talentId: Int) -> String? {
        heroTalents[TalentKey(classId: classId, specId: specId, talentId: talentId)]
    }
}
