import Foundation

/// 首领编号参考、字段参考、关于页文本（静态数据，与 Windows 版一致）。
public enum ReferenceData {
    public struct Boss: Sendable, Identifiable, Hashable {
        public let sequence: Int
        public let name: String
        public let number: Int
        public var id: Int { number }
    }

    public struct Dungeon: Sendable, Identifiable, Hashable {
        public let name: String
        public let bosses: [Boss]
        public var id: String { name }
    }

    public struct BossGroup: Sendable, Identifiable, Hashable {
        public let title: String
        public let dungeons: [Dungeon]
        public var id: String { title }
    }

    public static let currentSeasonDungeonNames: [String] = [
        "烈毒之渊", "潮缚石窟", "毒牙祭坛", "纳洛拉克的洞穴", "密谋小径", "夺目谷", "诸王之眠", "红玉新生法池", "虚空之痕竞技场", "塞塔里斯神庙"
    ]

    private static func d(_ name: String, _ bosses: [(Int, String, Int)]) -> Dungeon {
        Dungeon(name: name, bosses: bosses.map { Boss(sequence: $0.0, name: $0.1, number: $0.2) })
    }

    public static let bossGroups: [BossGroup] = [
        BossGroup(title: "", dungeons: [
            d("虚影尖塔", [(1, "元首阿福扎恩", 1), (2, "弗拉希乌斯", 2), (3, "陨落之王萨哈达尔", 3), (4, "威厄高尔和艾佐拉克", 4), (5, "光盲先锋军", 5), (6, "宇宙之冕", 6)]),
            d("梦境裂隙", [(1, "奇美鲁斯，未梦之神", 7)]),
            d("奎尔丹纳斯岛", [(1, "贝洛朗，奥的子嗣", 8), (2, "至暗之夜降临", 9)]),
            d("世界", [(1, "鲁阿夏尔", 10), (2, "索姆贝兰", 11), (3, "普雷达萨斯", 12), (4, "克拉格平", 13)]),
            d("孢陨幽境", [(1, "腐沼", 14)]),
            d("潮缚石窟", [(1, "尼姆瑞莎·唤波者", 15)]),
            d("烈毒之渊", [(1, "盘魂者内克扎莉", 16), (2, "陵寝哨兵", 17), (3, "迷失的探险者", 18), (4, "万毒邪祟者瓦什尼克", 19), (5, "斯索拉克", 20), (6, "双子毒牙", 21), (7, "盘卷祭坛", 22), (8, "乌拉特克", 23)])
        ]),
        BossGroup(title: "大米", dungeons: [
            d("节点希纳斯", [(1, "核技工程长卡斯雷瑟", 51), (2, "核心守卫奈萨拉", 52), (3, "洛萨克森", 53)]),
            d("迈萨拉洞窟", [(1, "姆罗金和内克拉克斯", 54), (2, "沃达扎", 55), (3, "拉克图尔，聚魂之器", 56)]),
            d("风行者之塔", [(1, "烬晓", 57), (2, "被遗弃的二人组", 58), (3, "指挥官克罗鲁科", 59), (4, "无眠之心", 60)]),
            d("魔导师平台", [(1, "奥能金刚库斯托斯", 61), (2, "瑟拉奈尔·日鞭", 62), (3, "吉美尔鲁斯", 63), (4, "迪詹崔乌斯", 64)]),
            d("执政团之座", [(1, "晋升者祖拉尔", 65), (2, "萨普瑞什", 66), (3, "总督奈扎尔", 67), (4, "鲁拉", 68)]),
            d("艾杰斯亚学院", [(1, "维克萨姆斯", 69), (2, "茂林古树", 70), (3, "克罗兹", 71), (4, "多拉苟萨的回响", 72)]),
            d("萨隆矿坑", [(1, "熔炉之主加弗斯特", 73), (2, "伊克和科瑞克", 74), (3, "天灾领主泰兰努斯", 75)]),
            d("通天峰", [(1, "兰吉特", 76), (2, "阿拉卡纳斯", 77), (3, "鲁克兰", 78), (4, "高阶贤者维里克斯", 79)]),
            d("毒牙祭坛", [(1, "拉维", 80), (2, "扭缠盘蛇", 81), (3, "祖尔加", 82)]),
            d("纳洛拉克的洞穴", [(1, "囤宝狂人", 83), (2, "寒冬哨兵", 84), (3, "纳洛拉克", 85)]),
            d("密谋小径", [(1, "凯斯媞亚·魔力之心", 86), (2, "赞恩·刃悲", 87), (3, "歼灭者萨祖克斯", 88), (4, "利希尔·烬怒", 89)]),
            d("夺目谷", [(1, "光明众花", 90), (2, "圣光猎手伊库兹", 91), (3, "护光者鲁伊亚", 92), (4, "兹欧凯特", 93)]),
            d("诸王之眠", [(1, "黄金风蛇", 94), (2, "部族议会", 95), (3, "殓尸者姆沁巴", 96), (4, "达萨大王", 97)]),
            d("红玉新生法池", [(1, "梅莉杜莎·寒妆", 98), (2, "柯姬雅·焰蹄", 99), (3, "基拉卡与厄克哈特·风脉", 100)]),
            d("虚空之痕竞技场", [(1, "塔兹拉尔", 101), (2, "阿特洛苏斯", 102), (3, "煞戎努斯", 103)]),
            d("塞塔里斯神庙", [(1, "阿德里斯和阿斯匹克斯", 104), (2, "米利克萨", 105), (3, "加瓦兹特", 106), (4, "塞塔里斯的化身", 107)])
        ])
    ]

    /// 按当前赛季与第一赛季整理的首领分组。
    public static let seasonBossGroups: [BossGroup] = {
        let dungeons = bossGroups.flatMap(\.dungeons)
        let current = dungeons
            .filter { currentSeasonDungeonNames.contains($0.name) }
            .sorted {
                (currentSeasonDungeonNames.firstIndex(of: $0.name) ?? .max)
                    < (currentSeasonDungeonNames.firstIndex(of: $1.name) ?? .max)
            }
        let first = dungeons.filter { !currentSeasonDungeonNames.contains($0.name) }
        return [
            BossGroup(title: "当前赛季", dungeons: current),
            BossGroup(title: "第一赛季", dungeons: first)
        ]
    }()

    public struct BossOption: Sendable, Identifiable, Hashable {
        public let number: Int
        public let dungeon: String
        public let name: String
        public var id: Int { number }
        public var display: String { "\(number) | \(dungeon) / \(name)" }
    }

    /// 去重、按编号排序的首领选项（条件编辑器 首领战 值选择器）。
    public static let bossOptions: [BossOption] = {
        var seen = Set<Int>()
        var result: [BossOption] = []
        for group in bossGroups {
            for dungeon in group.dungeons {
                for boss in dungeon.bosses where seen.insert(boss.number).inserted {
                    result.append(BossOption(number: boss.number, dungeon: dungeon.name, name: boss.name))
                }
            }
        }
        return result.sorted { $0.number < $1.number }
    }()

    public static func bossName(number: Int) -> String? {
        bossOptions.first { $0.number == number }.map { "\($0.dungeon) / \($0.name)" }
    }

    /// 字段参考页（分类 → 字段名）。
    public static let commonFieldCards: [(title: String, names: [String])] = [
        ("状态", ClassStateCatalog.names(in: ClassStateCatalog.categoryState).filter { $0 != "职业" && $0 != "专精" }),
        ("特殊", ClassStateCatalog.names(in: ClassStateCatalog.categorySpecial)),
        ("能量", ClassStateCatalog.names(in: ClassStateCatalog.categoryResource).filter { $0 != "符文" }),
        ("配置开关", ClassStateCatalog.names(in: ClassStateCatalog.categoryConfig)),
        ("物品", ["治疗药水", "魔法药水", "治疗石", "鲁莽药水", "圣光潜力"]),
        ("目标", ClassStateCatalog.names(in: ClassStateCatalog.categoryTarget).filter { $0 != "驱散类型" }),
        ("焦点", ClassStateCatalog.names(in: ClassStateCatalog.categoryFocus).filter { $0 != "驱散类型" }),
        ("鼠标", ClassStateCatalog.names(in: ClassStateCatalog.categoryMouseover).filter { $0 != "驱散类型" }),
        ("宠物", ClassStateCatalog.names(in: ClassStateCatalog.categoryPet))
    ]

    public static let productName = "Shigure"
    public static let productTagline = "Shigure 是荒坂公司（Arasaka Corporation）开发的冲锋枪。有时人们只想把子弹全打出去，在硝烟过后品味眼前的一片狼藉。"
    public static let moduleSiteURL = URL(string: "https://www.shigure.club")!
    public static let releasesPageURL = URL(string: "https://github.com/waynebian01/Shigure/releases")!

    public static let disclaimer = """
    1. 合规责任

    Shigure 仅供技术研究、学习交流和个人实验使用。下载、安装、复制、修改、分发或使用本软件前，用户应自行确认相关行为符合所在地法律法规，以及目标软件、游戏平台或服务提供商的用户协议、服务条款和社区规则。

    2. 账号与处罚风险

    本软件可能涉及窗口状态读取、按键发送或自动化辅助流程。此类行为可能被游戏运营商、反作弊系统或相关服务提供商认定为违规，并导致账号限制、角色封禁、数据丢失、收益回收或其他处罚。用户应充分了解并自行承担全部风险，开发者不对由此产生的任何后果负责。

    3. 无担保声明

    本项目基于 MIT License 开源发布。软件按“原样”（AS IS）提供，不对稳定性、准确性、完整性、安全性、兼容性、持续可用性或特定用途适用性作出任何明示或暗示保证。因使用或无法使用本软件导致的直接、间接、偶然、特殊或后续损失，均由用户自行承担。

    4. 商业使用与衍生版本

    MIT License 允许在遵守许可证条件的前提下复制、修改、分发和商业使用本软件。任何第三方对本软件或其衍生版本的运营、销售、推广、技术支持或其他商业利用，均由该第三方独立负责。开发者不代表、不授权或保证任何第三方产品、服务或运营活动，也不对第三方的违法行为、违反平台规则的行为或由此产生的后果负责。
    但本声明不限制适用法律所规定的责任，也不构成对任何具体行为合法性的保证。

    5. 使用即表示接受

    使用者应在使用前阅读并理解本免责声明及 MIT License。开始使用本软件，表示使用者已获得必要授权，并将自行承担使用本软件产生的风险；但仅通过使用行为是否构成法律上的合同接受，应以适用法律及实际使用场景为准。
    """

    public static let mitLicense = """
    MIT License

    Copyright (c) 2026 waynebian01

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    public static let attributions: [(title: String, body: String)] = [
        ("界面图标来源", "SF Symbols\n\nApple 系统符号库，随 macOS 提供。\n\n本软件的界面图标使用系统符号。"),
        ("技能与物品图标来源", "Clean Icons - Mechagnome Edition\n\nhttps://github.com/AcidWeb/Clean-Icons-Mechagnome-Edition\n\nUpscaled icon pack for World of Warcraft.\n\n本软件的技能与物品图标来自该项目。"),
        ("数据来源", "wow-listfile\n\nhttps://github.com/wowdev/wow-listfile\n\nA listfile for WoW archived files.\n\n本软件的部分文件名与资源索引数据来自该项目。")
    ]
}
