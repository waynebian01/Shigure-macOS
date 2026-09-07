import Foundation

/// 用户数据根目录布局（默认 ~/Library/Application Support/Shigure）。
/// 所有可变数据（Senkoh 源、config、keymap、module、data、settings）都在这里；
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

    public var senkohDirectory: URL { root.appendingPathComponent("Senkoh", isDirectory: true) }
    public var senkohClassDirectory: URL { senkohDirectory.appendingPathComponent("class", isDirectory: true) }
    public var classMacrosFile: URL { senkohDirectory.appendingPathComponent("core/classmacros.lua") }
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
        senkohClassDirectory.appendingPathComponent("\(ClassNames.configFileName(classId)).lua")
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
        for name in ["Senkoh", "config", "keymap"] {
            let target = root.appendingPathComponent(name, isDirectory: true)
            let source = resources.appendingPathComponent(name, isDirectory: true)
            guard !fm.fileExists(atPath: target.path), fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: target)
        }
    }

    /// 用户会在 app 内编辑的插件文件：框架升级时绝不覆盖。
    public static func isUserEditableAddonFile(_ relativePath: String) -> Bool {
        relativePath == "core/classmacros.lua" || relativePath.hasPrefix("class/")
    }

    /// 每次启动（seed 之后）：把内置 Senkoh 框架文件按 SHA-256 升级到用户数据目录。
    /// 只覆盖非用户编辑的文件；内置有而用户目录缺失的文件会补齐；用户目录多出的文件不删除。
    /// 返回实际更新的相对路径（升序）。
    public func upgradeFrameworkFiles(fromBundleResources resources: URL) throws -> [String] {
        let fm = FileManager.default
        let source = resources.appendingPathComponent("Senkoh", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue,
              fm.fileExists(atPath: senkohDirectory.path),
              let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let basePath = source.standardizedFileURL.path
        var updated: [String] = []
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(basePath.count + 1))
            if Self.isUserEditableAddonFile(relative) { continue }
            let target = senkohDirectory.appendingPathComponent(relative)
            if fm.fileExists(atPath: target.path), try SenkohAddonSync.sha256(file) == SenkohAddonSync.sha256(target) { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: file, to: target)
            updated.append(relative)
        }
        return updated.sorted()
    }
}

public enum AppInfo {
    /// 与模块 `Version` 字段比较（ordinal）。与 Windows 版保持一致以便共享模块文件。
    public static let version = "1.2.1.23"
    public static let company = "Arasaka Corporation"
}
