import Foundation
import CryptoKit

/// 由游戏 .app 位置向上寻找 Interface/AddOns（对应 C# WowAddonLocator）。
public enum WowAddonLocator {
    /// `/Applications/World of Warcraft/_retail_/World of Warcraft.app` → `.../_retail_/Interface/AddOns`。
    /// 祖先目录都没有 Interface 时返回 .app 同级的预期路径。
    public static func findAddOnsDirectory(bundleURL: URL) -> URL {
        var dir = bundleURL.deletingLastPathComponent()
        let fm = FileManager.default
        while dir.path.count > 1 {
            let interfaceDir = dir.appendingPathComponent("Interface", isDirectory: true)
            let addOnsDir = interfaceDir.appendingPathComponent("AddOns", isDirectory: true)
            if fm.fileExists(atPath: addOnsDir.path) || fm.fileExists(atPath: interfaceDir.path) {
                return addOnsDir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return bundleURL.deletingLastPathComponent().appendingPathComponent("Interface/AddOns", isDirectory: true)
    }

    public static func addonRoot(bundleURL: URL) -> URL {
        findAddOnsDirectory(bundleURL: bundleURL).appendingPathComponent("Senkoh", isDirectory: true)
    }
}

public struct AddonSyncResult: Sendable {
    public let sourceRoot: URL
    public let targetRoot: URL?
    public let copiedFiles: [String]
    public let skippedFiles: [String]
    public let failures: [(path: String, message: String)]
    public let skippedReason: String?

    public var targetFound: Bool { targetRoot != nil }
    public var completedSuccessfully: Bool { targetFound && failures.isEmpty }

    public var summary: String {
        if let reason = skippedReason { return reason }
        var text = "已复制 \(copiedFiles.count) 个文件，\(skippedFiles.count) 个相同文件跳过 → \(targetRoot?.path ?? "-")"
        if !failures.isEmpty { text += "；\(failures.count) 个文件失败：\(failures.prefix(3).map { "\($0.path): \($0.message)" }.joined(separator: "；"))" }
        return text
    }
}

/// 项目内 Senkoh/ 是唯一权威源：按 SHA-256 单向部署到游戏 AddOns（不删除目标额外文件）。
public enum SenkohAddonSync {
    public static func synchronizeAll(sourceRoot: URL, targetRoot: URL?) throws -> AddonSyncResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw LuaStoreError("找不到内置 Senkoh 目录: \(sourceRoot.path)")
        }
        guard let targetRoot else {
            return AddonSyncResult(sourceRoot: sourceRoot, targetRoot: nil, copiedFiles: [], skippedFiles: [], failures: [], skippedReason: "未找到目标游戏进程, 已跳过游戏插件同步。")
        }
        var copied: [String] = []
        var skipped: [String] = []
        var failures: [(String, String)] = []
        guard let enumerator = fm.enumerator(at: sourceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return AddonSyncResult(sourceRoot: sourceRoot, targetRoot: targetRoot, copiedFiles: [], skippedFiles: [], failures: [], skippedReason: nil)
        }
        let basePath = sourceRoot.standardizedFileURL.path
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(basePath.count + 1))
            synchronizeCore(source: file, relative: relative, targetRoot: targetRoot, copied: &copied, skipped: &skipped, failures: &failures)
        }
        return AddonSyncResult(sourceRoot: sourceRoot, targetRoot: targetRoot, copiedFiles: copied, skippedFiles: skipped,
                               failures: failures.map { (path: $0.0, message: $0.1) }, skippedReason: nil)
    }

    /// 只同步一个文件（保存 Lua 后的单文件部署）。relativePath 不得越出源目录。
    public static func synchronizeFile(sourceRoot: URL, targetRoot: URL?, relativePath: String) throws -> AddonSyncResult {
        guard !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else {
            throw LuaStoreError("非法的相对路径: \(relativePath)")
        }
        guard let targetRoot else {
            return AddonSyncResult(sourceRoot: sourceRoot, targetRoot: nil, copiedFiles: [], skippedFiles: [], failures: [], skippedReason: "未找到目标游戏进程, 已跳过游戏插件同步。")
        }
        var copied: [String] = []
        var skipped: [String] = []
        var failures: [(String, String)] = []
        synchronizeCore(source: sourceRoot.appendingPathComponent(relativePath), relative: relativePath, targetRoot: targetRoot, copied: &copied, skipped: &skipped, failures: &failures)
        return AddonSyncResult(sourceRoot: sourceRoot, targetRoot: targetRoot, copiedFiles: copied, skippedFiles: skipped,
                               failures: failures.map { (path: $0.0, message: $0.1) }, skippedReason: nil)
    }

    private static func synchronizeCore(source: URL, relative: String, targetRoot: URL, copied: inout [String], skipped: inout [String], failures: inout [(String, String)]) {
        let fm = FileManager.default
        let target = targetRoot.appendingPathComponent(relative)
        do {
            if fm.fileExists(atPath: target.path), try sha256(source) == sha256(target) {
                skipped.append(relative)
                return
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
            copied.append(relative)
        } catch {
            failures.append((relative, error.localizedDescription))
        }
    }

    public static func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
