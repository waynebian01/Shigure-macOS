import Foundation

/// ClassBlocks states 可选字段目录。
public enum ClassStateCatalog {
    public static let categoryState = "状态"
    public static let categoryPlayerDisplay = "玩家"
    public static let categorySpecial = "特殊"
    public static let categoryConfig = "配置开关"
    public static let categoryItem = "物品"
    public static let categoryResource = "能量"
    public static let categoryTarget = "目标"
    public static let categoryFocus = "焦点"
    public static let categoryMouseover = "鼠标"
    public static let categoryPet = "宠物"
    public static let categoryBoss1 = "首领1"
    public static let categoryBoss2 = "首领2"
    public static let categoryBoss3 = "首领3"
    public static let categoryBoss4 = "首领4"
    public static let categoryBoss5 = "首领5"

    public static let legacyItemIds: [String: Int64] = [
        "治疗药水": 241304, "魔法药水": 241301, "治疗石": 5512, "鲁莽药水": 241288, "圣光潜力": 241308
    ]

    /// 13 个存储分类，固定顺序（Lua 序列化、config 转换、依赖导入共用）。
    public static let topCategories: [String] = [
        categoryState, categorySpecial, categoryResource, categoryConfig,
        categoryTarget, categoryFocus, categoryMouseover, categoryPet,
        categoryBoss1, categoryBoss2, categoryBoss3, categoryBoss4, categoryBoss5
    ]

    private static let unitFields = ["类型", "驱散类型", "生命值", "距离", "施法(倒计时)", "施法(正计时)", "施法可打断", "引导", "引导可打断"]

    /// 声明顺序决定 findCategory 的优先级（"符文" 先命中 特殊）。
    static let categories: [(category: String, names: [String])] = [
        (categoryState, [
            "职业", "专精", "有效性", "战斗时间", "移动",
            "生命值", "一键辅助", "插入法术", "插入物品", "队伍类型", "队伍人数",
            "首领战", "难度", "英雄天赋", "施法目标", "施法技能",
            "敌人数量", "敌人数-无仇恨", "敌人数-有仇恨",
            "施法(正计时)", "施法(倒计时)", "引导", "蓄力", "蓄力层数",
            "上个技能", "公共冷却"
        ]),
        (categorySpecial, [
            "计时器", "循环计时器", "战斗计时(秒)", "战斗计时(分)",
            "酒池", "符文", "姿态", "神圣军备", "自律", "天启骑士数量",
            "英勇打击", "吸血鬼打击", "收割者战刃", "沸点",
            "风暴涌流图腾", "风暴涌流图腾数量", "治疗之泉图腾", "治疗之泉图腾数量"
        ]),
        (categoryConfig, ["爆发开关", "AOE开关", "输出模式", "爆发药水开关", "延迟"]),
        (categoryResource, [
            "法力值", "怒气值", "集中值", "能量值", "符文", "符文能量",
            "星界能量", "漩涡值", "狂乱值", "奥术充能", "恶魔之怒", "痛苦值",
            "连击点", "神圣能量", "精华能量", "灵魂碎片", "真气", "增压层数"
        ]),
        (categoryTarget, unitFields),
        (categoryFocus, unitFields),
        (categoryMouseover, unitFields),
        (categoryPet, ["存在", "生命值"]),
        (categoryBoss1, unitFields),
        (categoryBoss2, unitFields),
        (categoryBoss3, unitFields),
        (categoryBoss4, unitFields),
        (categoryBoss5, unitFields)
    ]

    public static func names(in category: String) -> [String] {
        categories.first { $0.category == category }?.names ?? []
    }

    public static func displayName(of category: String) -> String {
        category == categoryState ? categoryPlayerDisplay : category
    }

    public static func storageCategory(fromDisplay displayName: String) -> String {
        displayName == categoryPlayerDisplay ? categoryState : displayName
    }

    public static func isKnown(category: String, name: String) -> Bool {
        !name.isBlank && names(in: category).contains(name)
    }

    public static func findCategory(_ name: String) -> String? {
        categories.first { $0.names.contains(name) }?.category
    }

    /// 带单位前缀的字段（目标生命值）归到该单位分类，否则按目录查找，默认 状态。
    public static func classifyField(_ name: String) -> String {
        if name.isBlank { return categoryState }
        for category in topCategories where isUnitPrefixCategory(category) && name.hasPrefix(category) {
            return category
        }
        return findCategory(name) ?? categoryState
    }

    public static func isUnitPrefixCategory(_ category: String) -> Bool {
        [categoryTarget, categoryFocus, categoryMouseover, categoryPet,
         categoryBoss1, categoryBoss2, categoryBoss3, categoryBoss4, categoryBoss5].contains(category)
    }

    /// Lua 中已有但目录尚未收录的状态仍放在“状态”中，保证可见、可编辑。
    public static func isInCategory(name: String, category: String) -> Bool {
        if isKnown(category: category, name: name) { return true }
        return category == categoryState && findCategory(name) == nil
    }

    public static func legacyItemId(for name: String) -> Int64? {
        legacyItemIds[name]
    }
}
