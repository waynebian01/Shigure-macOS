import Foundation

/// 按键注入方式。
public enum KeyInjectionMode: String, Sendable, Codable, CaseIterable {
    /// CGEvent.postToPid：投递给游戏进程，不需要游戏在前台。
    case process
    /// CGEvent.post(tap: .cghidEventTap)：系统级输入，需要游戏在前台。
    case system

    public var displayName: String {
        switch self {
        case .process: return "投递到游戏进程"
        case .system: return "系统级输入（需前台）"
        }
    }
}

/// 持久化设置（{root}/settings.json）。对应 Windows 版 window-state.json 中的非窗口字段。
public struct AppSettings: Sendable, Codable, Equatable {
    public var toggleKey = "XBUTTON2"
    public var sendMode: SendMode = .switch
    public var logicMs = 100
    public var renderMs = 100
    public var selectedModuleId: String?
    public var defaultModules: [DefaultModuleSelection] = []
    public var gameBundleIdentifiers: [String] = ["com.blizzard.worldofwarcraft"]
    public var keyInjectionMode: KeyInjectionMode = .process
    public var selectedPage: String?
    public var autoStartRuntime = true
    /// 用户显式指定的游戏 .app 路径（正式服/怀旧服共用 bundle id 时用于消歧）。
    public var gameAppPath: String?

    public init() {}

    public var options: AppOptions {
        AppOptions(toggleKey: toggleKey, mode: sendMode, moduleId: selectedModuleId, logicMs: logicMs, renderMs: renderMs)
    }

    public static func load(from url: URL) -> AppSettings {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return decoded
        }
        // 首次运行：从早期版本的 cache/settings.json 迁移少量字段。
        var settings = AppSettings()
        let legacy = url.deletingLastPathComponent().appendingPathComponent("cache/settings.json")
        if let text = try? TextFile.read(legacy), let obj = try? JSONParser.parseObject(text) {
            if let key = obj["toggleKey"]?.stringValue, !key.isBlank { settings.toggleKey = key }
            if let mode = obj["sendMode"]?.stringValue, let parsed = SendMode(rawValue: mode) { settings.sendMode = parsed }
            if let ms = JSONHelpers.getInt(obj["logicIntervalMilliseconds"]) { settings.logicMs = max(50, ms) }
            if let ms = JSONHelpers.getInt(obj["renderIntervalMilliseconds"]) { settings.renderMs = max(100, ms) }
        }
        return settings
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFile.write(try encoder.encode(self), to: url)
    }
}
