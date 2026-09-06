import Foundation

/// 用户数据根目录布局（默认 ~/Library/Application Support/Shigure）。
/// 所有可变数据（Fuyutsui 源、config、keymap、module、data、settings）都在这里；
/// .app 内置资源只作为首次启动的种子。
public struct AppPaths: Sendable {
    public static let appName = "Shigure"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func defaultUserData() -> AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AppPaths(root: base.appendingPathComponent(appName, isDirectory: true))
    }

    public var fuyutsuiDirectory: URL { root.appendingPathComponent("Fuyutsui", isDirectory: true) }
    public var fuyutsuiClassDirectory: URL { fuyutsuiDirectory.appendingPathComponent("class", isDirectory: true) }
    public var classMacrosFile: URL { fuyutsuiDirectory.appendingPathComponent("core/classmacros.lua") }
    public var configDirectory: URL { root.appendingPathComponent("config", isDirectory: true) }
    public var keymapDirectory: URL { root.appendingPathComponent("keymap", isDirectory: true) }
    public var moduleDirectory: URL { root.appendingPathComponent("module", isDirectory: true) }
    public var dataDirectory: URL { root.appendingPathComponent("data", isDirectory: true) }
    public var iconPackFile: URL { dataDirectory.appendingPathComponent("SpellIcons.shgpack") }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    public var logDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/\(AppPaths.appName)", isDirectory: true)
    }

    public func classLuaFile(classId: Int) -> URL {
        fuyutsuiClassDirectory.appendingPathComponent("\(ClassNames.configFileName(classId)).lua")
    }

    public func ensureDirectories() throws {
        for dir in [root, moduleDirectory, dataDirectory] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 首次启动：把内置资源复制到用户数据目录（只复制缺失的顶层目录，不覆盖用户修改）。
    public func seed(fromBundleResources resources: URL) throws {
        try ensureDirectories()
        let fm = FileManager.default
        for name in ["Fuyutsui", "config", "keymap"] {
            let target = root.appendingPathComponent(name, isDirectory: true)
            let source = resources.appendingPathComponent(name, isDirectory: true)
            guard !fm.fileExists(atPath: target.path), fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: target)
        }
    }
}

public enum AppInfo {
    /// 与模块 `Version` 字段比较（ordinal）。与 Windows 版保持一致以便共享模块文件。
    public static let version = "1.2.1.23"
    public static let company = "Arasaka Corporation"
}
