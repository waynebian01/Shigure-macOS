import Foundation

/// 随模块分发的职业配置与宏快照。
public struct ModuleDependencySnapshot: Sendable, Equatable {
    public static let currentSchemaVersion = 2

    public var schemaVersion = currentSchemaVersion
    public var classId = 0
    public var specId = 0
    public var config = ModuleConfigSnapshot()
    public var macros = ModuleMacrosSnapshot()

    public init() {}
}

public struct ModuleConfigSnapshot: Sendable, Equatable {
    public var spec = ModuleSpecSnapshot()
    public var spellsList: [ModuleSpellListEntrySnapshot] = []
    public var itemsList: [ModuleItemListEntrySnapshot] = []
    public init() {}
}

public struct ModuleSpecSnapshot: Sendable, Equatable {
    public var nestedStates = true
    public var flatStates: [String] = []
    public var categorizedStates: [String: [String]] = [:]
    public var items: [ModuleItemSnapshot] = []
    public var playerAuras: [ModuleAuraSnapshot] = []
    public var targetHarmfulAuras: [ModuleAuraSnapshot] = []
    public var targetHelpfulAuras: [ModuleAuraSnapshot] = []
    public var focusHarmfulAuras: [ModuleAuraSnapshot] = []
    public var focusHelpfulAuras: [ModuleAuraSnapshot] = []
    public var spells: [ModuleSpellSnapshot] = []
    public var group: ModuleGroupSnapshot?
    public init() {}
}

public struct ModuleItemSnapshot: Sendable, Equatable {
    public var itemId: Int64 = 0
    public var name = ""
    public var isEquipped = false
    public init(itemId: Int64 = 0, name: String = "", isEquipped: Bool = false) {
        self.itemId = itemId; self.name = name; self.isEquipped = isEquipped
    }
}

public struct ModuleAuraSnapshot: Sendable, Equatable {
    public var name = ""
    public var spellId: Int64?
    public var spellIds: [Int64] = []
    public var maxApps: Int?
    public init(name: String = "", spellId: Int64? = nil, spellIds: [Int64] = [], maxApps: Int? = nil) {
        self.name = name; self.spellId = spellId; self.spellIds = spellIds; self.maxApps = maxApps
    }
}

public struct ModuleSpellSnapshot: Sendable, Equatable {
    public var name = ""
    public var spellId: Int64 = 0
    public var charge = false
    public var maxCharge: Int?
    public var castCount: Int?
    public var forcedKnown = false
    public var inSpellBook = false
    public init() {}
}

public struct ModuleSpellListEntrySnapshot: Sendable, Equatable {
    public var spellId: Int64 = 0
    public var index = 0
    public var name = ""
    public init(spellId: Int64 = 0, index: Int = 0, name: String = "") {
        self.spellId = spellId; self.index = index; self.name = name
    }
}

public struct ModuleItemListEntrySnapshot: Sendable, Equatable {
    public var itemId: Int64 = 0
    public var index = 0
    public var name = ""
    public init(itemId: Int64 = 0, index: Int = 0, name: String = "") {
        self.itemId = itemId; self.index = index; self.name = name
    }
}

public struct ModuleGroupSnapshot: Sendable, Equatable {
    public var num = 5
    public var healthPercent: Int?
    public var role: Int?
    public var dispel: Int?
    public var auras: [ModuleGroupAuraSnapshot] = []
    public init() {}
}

public struct ModuleGroupAuraSnapshot: Sendable, Equatable {
    public var offset = 0
    public var name = ""
    public var spellId: Int64?
    public var spellIds: [Int64] = []
    public init() {}
}

public struct ModuleMacrosSnapshot: Sendable, Equatable {
    public var usesSpecDynamicSpells = false
    public var dynamicCommon: [String] = []
    public var dynamicForSpec: [String] = []
    public var staticSpells: [ModuleMacroEntrySnapshot] = []
    public var specialSpells: [ModuleMacroEntrySnapshot] = []
    public init() {}
}

public struct ModuleMacroEntrySnapshot: Sendable, Equatable {
    public var text = ""
    public var comment: String?
    public init(text: String = "", comment: String? = nil) {
        self.text = text
        self.comment = comment
    }
}
