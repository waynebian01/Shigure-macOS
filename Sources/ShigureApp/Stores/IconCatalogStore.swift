import AppKit
import Observation
import ShigureCore

/// 技能/物品图标与名称目录（对应 C# SpellIconCatalog）。
/// 名称来源：数据包 + 从职业 Lua 注册的名称；图标来源：数据包 + 内置少量特殊图标。
@MainActor
@Observable
final class IconCatalogStore {
    let packageURL: URL
    private(set) var reader: ShgPackReader?
    private(set) var version = 0
    private(set) var loadError: String?

    @ObservationIgnored private var spellImages: [Int64: NSImage] = [:]
    @ObservationIgnored private var itemImages: [Int64: NSImage] = [:]
    @ObservationIgnored private var classImages: [Int: NSImage] = [:]
    @ObservationIgnored private var specImages: [String: NSImage] = [:]
    private var registeredSpellNames: [Int64: String] = [:]
    private var registeredSpellIds: [String: Int64] = [:]
    private var registeredItemNames: [Int64: String] = [:]
    private var registeredItemIds: [String: Int64] = [:]

    /// 内置的特殊动作/物品图标（Resources/Icons/Spell）。
    private static let namedResources: [String: String] = [
        ModuleSpecialActions.pauseSpell: "pause.png",
        ModuleSpecialActions.oneKeySpell: "one-key-spell.png",
        ModuleSpecialActions.failedSpell: "auto-insert-spell.png",
        ModuleSpecialActions.failedItem: "auto-insert-spell.png",
        "鲁莽药水": "recklessness-potion.jpg",
        "圣光潜力": "lights-potential.jpg",
        "光注法力药水": "light-infused-mana-potion.jpg",
        "十字军打击": "crusader-strike.png",
        "停止施法": "stop-casting.png"
    ]
    private static let spellIdResources: [Int64: String] = [241288: "recklessness-potion.jpg", 241308: "lights-potential.jpg", 241300: "light-infused-mana-potion.jpg"]
    @ObservationIgnored private var namedImages: [String: NSImage] = [:]

    init(packageURL: URL) {
        self.packageURL = packageURL
        reload()
    }

    var isPackageAvailable: Bool { reader != nil }
    var isItemDatabaseAvailable: Bool { reader?.hasItemDatabase ?? false }
    var packageSizeMiB: Double { Double(reader?.fileSize ?? 0) / 1024 / 1024 }

    func reload() {
        spellImages.removeAll()
        itemImages.removeAll()
        classImages.removeAll()
        specImages.removeAll()
        if FileManager.default.fileExists(atPath: packageURL.path) {
            do {
                reader = try ShgPackReader(url: packageURL)
                loadError = nil
            } catch {
                reader = nil
                loadError = "\(error)"
            }
        } else {
            reader = nil
            loadError = nil
        }
        version += 1
    }

    // MARK: 名称

    func register(spellId: Int64, name: String?, overwrite: Bool = false) {
        guard spellId > 0, let name = name?.trimmed(), !name.isEmpty else { return }
        registeredSpellIds[name] = spellId
        if overwrite || registeredSpellNames[spellId] == nil { registeredSpellNames[spellId] = name }
    }

    func registerItem(itemId: Int64, name: String?) {
        guard itemId > 0, let name = name?.trimmed(), !name.isEmpty else { return }
        registeredItemIds[name] = itemId
        if registeredItemNames[itemId] == nil { registeredItemNames[itemId] = name }
    }

    /// 已注册名称优先，其次数据包。
    func spellName(_ spellId: Int64) -> String? {
        registeredSpellNames[spellId] ?? reader?.spellNamesById[spellId]
    }

    func itemName(_ itemId: Int64) -> String? {
        registeredItemNames[itemId] ?? reader?.itemNamesById[itemId]
    }

    func spellId(named name: String) -> Int64? {
        registeredSpellIds[name.trimmed()] ?? reader?.spellIdsByName[name.trimmed()]
    }

    func itemId(named name: String) -> Int64? {
        if let parsed = Self.parseItemReference(name) { return parsed }
        return registeredItemIds[name.trimmed()] ?? reader?.itemIdsByName[name.trimmed()]
    }

    static func parseItemReference(_ text: String) -> Int64? {
        let trimmed = text.trimmed()
        guard let range = trimmed.range(of: #"item:(\d+)"#, options: String.CompareOptions([.regularExpression, .caseInsensitive])) else { return nil }
        let digits = trimmed[range].dropFirst(5)
        guard let id = Int64(digits), id > 0 else { return nil }
        return id
    }

    /// 数据库建议列表（spellId, name），按 id 升序。
    var spellSuggestions: [(id: Int64, name: String)] {
        guard let reader else { return [] }
        return reader.allSpellIds.map { ($0, reader.spellNamesById[$0] ?? "") }
    }

    var itemSuggestions: [(id: Int64, name: String)] {
        guard let reader, reader.hasItemDatabase else { return [] }
        return reader.allItemIds.map { ($0, reader.itemNamesById[$0] ?? "") }
    }

    // MARK: 图标

    /// NSMenu（Picker/Menu 下拉）按 NSImage.size 原样渲染、忽略 SwiftUI 的 frame，
    /// 因此加载时统一把显示尺寸归一到菜单文字高度；像素数据不变，放大显示不受影响。
    private static func normalizedForMenu(_ image: NSImage) -> NSImage {
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    func image(id: Int64, isItem: Bool) -> NSImage? {
        isItem ? itemImage(id) : spellImage(id)
    }

    func spellImage(_ spellId: Int64) -> NSImage? {
        // 缓存填充不应让其它行失效；只有数据包换代才刷新已显示的图标。
        _ = version
        guard spellId > 0 else { return nil }
        if let cached = spellImages[spellId] { return cached }
        var image: NSImage?
        if let resource = Self.spellIdResources[spellId] { image = loadResource(resource) }
        if image == nil, let data = reader?.spellIconData(spellId) { image = NSImage(data: data).map(Self.normalizedForMenu) }
        if let image { spellImages[spellId] = image }
        return image
    }

    func itemImage(_ itemId: Int64) -> NSImage? {
        _ = version
        guard itemId > 0 else { return nil }
        if let cached = itemImages[itemId] { return cached }
        var image: NSImage?
        if let resource = Self.spellIdResources[itemId] { image = loadResource(resource) }
        if image == nil, let data = reader?.itemIconData(itemId) { image = NSImage(data: data).map(Self.normalizedForMenu) }
        if let image { itemImages[itemId] = image }
        return image
    }

    /// 按名称：特殊动作内置图标 → 已注册/数据包 spellId → 物品。
    func image(named name: String?) -> NSImage? {
        guard let name = name?.trimmed(), !name.isEmpty else { return nil }
        if let resource = Self.namedResources[name] { return loadResource(resource) }
        if let spellId = spellId(named: name), let image = spellImage(spellId) { return image }
        if let itemId = itemId(named: name) { return itemImage(itemId) }
        return nil
    }

    private func loadResource(_ fileName: String) -> NSImage? {
        if let cached = namedImages[fileName] { return cached }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Icons/Spell"), let image = NSImage(contentsOf: url).map(Self.normalizedForMenu) else { return nil }
        namedImages[fileName] = image
        return image
    }

    /// 职业图标 / 专精图标（Resources/Icons/Class|Spec）。
    func classImage(_ classId: Int) -> NSImage? {
        if let cached = classImages[classId] { return cached }
        let name = ClassNames.configFileName(classId).lowercased()
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Icons/Class") else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        classImages[classId] = image
        return image
    }

    func specImage(classId: Int, specId: Int) -> NSImage? {
        guard let name = ClassNames.specIconFileName(classId: classId, specId: specId),
              let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Icons/Spec") else { return nil }
        let key = "\(classId):\(specId)"
        if let cached = specImages[key] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        specImages[key] = image
        return image
    }
}
