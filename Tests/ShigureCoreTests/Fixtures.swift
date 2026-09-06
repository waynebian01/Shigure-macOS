import Foundation
import Testing
@testable import ShigureCore

enum Fixtures {
    static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    static func text(_ relative: String) throws -> String {
        try TextFile.read(url(relative))
    }

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: url(relative))
    }

    /// 临时目录，测试结束后自动删除。
    static func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shigure-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    static func makePaths(_ dir: URL) throws -> AppPaths {
        let paths = AppPaths(root: dir)
        try paths.ensureDirectories()
        let fm = FileManager.default
        try fm.copyItem(at: url("config"), to: paths.configDirectory)
        try fm.copyItem(at: url("keymap"), to: paths.keymapDirectory)
        try fm.createDirectory(at: paths.fuyutsuiDirectory, withIntermediateDirectories: true)
        try fm.copyItem(at: url("Fuyutsui/class"), to: paths.fuyutsuiClassDirectory)
        try fm.createDirectory(at: paths.fuyutsuiDirectory.appendingPathComponent("core"), withIntermediateDirectories: true)
        try fm.copyItem(at: url("Fuyutsui/core/classmacros.lua"), to: paths.classMacrosFile)
        return paths
    }
}
